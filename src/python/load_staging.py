"""
==============================================================================
Script: load_staging.py
Descrição: Ingestão de alta performance dos 9 CSVs da Olist para a camada
           de staging do PostgreSQL usando o protocolo streaming COPY.
Idempotência: Executa TRUNCATE em cada tabela antes da carga.
Filosofia ELT: Ingestão 100% tolerante em colunas TEXT.
==============================================================================
"""

import os
import sys
import time
from pathlib import Path
from dotenv import load_dotenv
import psycopg2
from psycopg2 import sql

# Mapeamento: Nome do arquivo CSV -> Nome da tabela no schema staging
DATASET_MAPPING = {
    "olist_orders_dataset.csv": "orders",
    "olist_order_items_dataset.csv": "order_items",
    "olist_order_payments_dataset.csv": "order_payments",
    "olist_order_reviews_dataset.csv": "order_reviews",
    "olist_customers_dataset.csv": "customers",
    "olist_sellers_dataset.csv": "sellers",
    "olist_products_dataset.csv": "products",
    "olist_geolocation_dataset.csv": "geolocation",
    "product_category_name_translation.csv": "product_category_name_translation",
}

# Carregar o .env antes de inicializar as variáveis
load_dotenv()

# Configurações de Conexão com o PostgreSQL
PG_HOST = os.getenv("PG_HOST", "localhost")
PG_PORT = int(os.getenv("PG_PORT", "5432"))
PG_DATABASE = os.getenv("PG_DATABASE", "postgres")
PG_USER = os.getenv("PG_USER", "postgres")
PG_PASSWORD = os.getenv("PG_PASSWORD", "postgres")


def find_project_root() -> Path:
    """Localiza a raiz do projeto bi-laboratorio-olist."""
    current = Path(__file__).resolve().parent.parent
    if (current.parent / "data" / "dataset").exists():
        return current.parent
    if (current / "data" / "dataset").exists():
        return current
    # Fallback
    return current.parent


def run_sql_file(cursor, file_path: Path):
    """Lê e executa um script SQL completo."""
    print(f"📄 Executando script DDL: {file_path.name}...")
    with open(file_path, "r", encoding="utf-8") as f:
        cursor.execute(f.read())


def load_csv_to_staging(cursor, csv_path: Path, table_name: str) -> dict:
    """
    Carrega um arquivo CSV para a tabela correspondente no schema staging
    utilizando TRUNCATE (idempotência) e COPY streaming para máxima performance.
    """
    start_time = time.time()
    
    print("Obter cabeçalho do CSV para mapeamento explícito de colunas")
    with open(csv_path, "r", encoding="utf-8-sig") as f:
        header_line = f.readline().strip()
        columns = [col.strip().replace('"', '').replace('\ufeff', '') for col in header_line.split(",")]
    
    columns_joined = ", ".join([f'"{col}"' for col in columns])
    
    print("Truncar tabela antes da carga")
    cursor.execute(sql.SQL("TRUNCATE TABLE staging.{} CASCADE;").format(sql.Identifier(table_name)))
    
    print("Realizar streaming COPY")
    copy_sql = f"""
        COPY staging.{table_name} ({columns_joined}) 
        FROM STDIN 
        WITH (FORMAT csv, HEADER true, DELIMITER ',', QUOTE '"');
    """
    
    print("Carregar dados via streaming COPY")
    with open(csv_path, "r", encoding="utf-8-sig", errors="replace") as f:
        cursor.copy_expert(sql=copy_sql, file=f)
    
    print("Validando contagem de linhas no banco")
    cursor.execute(sql.SQL("SELECT COUNT(*) FROM staging.{};").format(sql.Identifier(table_name)))
    count_db = cursor.fetchone()[0]
    
    elapsed = time.time() - start_time
    
    return {
        "file": csv_path.name,
        "table": f"staging.{table_name}",
        "rows": count_db,
        "time_seconds": elapsed,
        "rate": count_db / elapsed if elapsed > 0 else 0
    }


def main():
    root_dir = find_project_root()
    dataset_dir = root_dir / "data" / "dataset"
    sql_ddl_schemas = root_dir / "sql" / "ddl" / "01_create_schemas.sql"
    sql_ddl_staging = root_dir / "sql" / "staging" / "01_create_staging_tables.sql"
    
    print("=" * 80)
    print("🚀 INGESTÃO DE DADOS — CAMADA DE STAGING (POSTGRESQL)")
    print("=" * 80)
    print(f"Diretório Raiz: {root_dir}")
    print(f"Diretório Dataset: {dataset_dir}")
    print(f"Conexão: postgresql://{PG_USER}@{PG_HOST}:{PG_PORT}/{PG_DATABASE}")
    print("-" * 80)
    
    if not dataset_dir.exists():
        print(f"❌ Erro: Diretório de dados não encontrado: {dataset_dir}")
        sys.exit(1)
        
    try:
        conn = psycopg2.connect(
            host=PG_HOST,
            port=PG_PORT,
            dbname=PG_DATABASE,
            user=PG_USER,
            password=PG_PASSWORD
        )
        conn.autocommit = True
        cursor = conn.cursor()
        print("✅ Conexão com o PostgreSQL estabelecida com sucesso!")
    except Exception as e:
        print(f"❌ Falha ao conectar ao PostgreSQL: {e}")
        print("\n💡 Dica: Verifique se o container no Portainer está ativo e se as variáveis")
        print("   PG_HOST, PG_PORT, PG_DATABASE, PG_USER, PG_PASSWORD estão corretas.")
        sys.exit(1)

    try:
        # 1. Executar DDLs de preparação
        if sql_ddl_schemas.exists():
            run_sql_file(cursor, sql_ddl_schemas)
        if sql_ddl_staging.exists():
            run_sql_file(cursor, sql_ddl_staging)
        
        print("-" * 80)
        print("📥 Iniciando streaming dos 9 arquivos CSV para o schema staging...")
        print("-" * 80)
        
        results = []
        total_rows = 0
        total_start_time = time.time()
        
        for csv_filename, table_name in DATASET_MAPPING.items():
            csv_path = dataset_dir / csv_filename
            if not csv_path.exists():
                print(f"⚠️ Arquivo não encontrado: {csv_filename} (ignorando)")
                continue
            
            print(f"⏳ Carregando {csv_filename} -> staging.{table_name}...", end=" ", flush=True)
            res = load_csv_to_staging(cursor, csv_path, table_name)
            results.append(res)
            total_rows += res["rows"]
            print(f"✅ {res['rows']:,} linhas ({res['time_seconds']:.2f}s | {res['rate']:,.0f} lin/s)")
            
        total_elapsed = time.time() - total_start_time
        
        print("=" * 80)
        print("📊 RESUMO DA INGESTÃO (STAGING POSTGRESQL)")
        print("=" * 80)
        print(f"{'Tabela Staging':<35} | {'Linhas Inseridas':>16} | {'Tempo (s)':>10} | {'Throughput':>14}")
        print("-" * 80)
        for r in results:
            print(f"{r['table']:<35} | {r['rows']:>16,d} | {r['time_seconds']:>9.2f}s | {r['rate']:>11,.0f} lin/s")
        print("-" * 80)
        print(f"Total Ingerido: {total_rows:,} registros em {total_elapsed:.2f} segundos ({total_rows/total_elapsed:,.0f} lin/s)")
        print("=" * 80)
        print("🎉 Ingestão concluída com sucesso! Camada de staging pronta para auditoria.")
        
    except Exception as e:
        print(f"\n❌ Erro durante a ingestão: {e}")
        sys.exit(1)
    finally:
        cursor.close()
        conn.close()


if __name__ == "__main__":
    main()
