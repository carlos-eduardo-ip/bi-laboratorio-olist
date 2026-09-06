-- ==============================================================================
-- Script: 01_create_dw_dimensions.sql
-- Descrição: Criação das Tabelas Dimensão do Data Warehouse (Kimball Star Schema / Outrigger)
-- Schema: dw
-- Decisões Aplicadas:
--   - Surrogate Keys inteiras (INT GENERATED ALWAYS AS IDENTITY) para performance
--   - dim_geografia centralizada: consolida coordenadas (lat/lng) e hierarquias regionais
--   - dim_cliente com SCD Tipo 2 e chave estrangeira para dim_geografia
--   - dim_vendedor com chave estrangeira para dim_geografia
--   - dim_calendario canônica Kimball (sk_data no formato YYYYMMDD)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Dimensão: dw.dim_geografia (Dimensão Central de Localização e Coordenadas)
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS dw.dim_geografia CASCADE;

CREATE TABLE dw.dim_geografia (
    -- Chave Substituta
    sk_geografia                INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,    
    -- Chave Natural / Junção com os cadastros
    zip_code_prefix             VARCHAR(5)   NOT NULL UNIQUE,    
    -- Atributos Descritivos Geográficos
    cidade                      VARCHAR(100) NOT NULL,
    estado                      VARCHAR(2)   NOT NULL,
    regiao                      VARCHAR(20)  NOT NULL, -- Sudeste, Sul, Nordeste, Centro-Oeste, Norte    
    -- Coordenadas Espaciais Médias Consolidadas (para mapas no Power BI)
    latitude                    NUMERIC(10,6),
    longitude                   NUMERIC(10,6),    
    -- Auditoria de Carga
    data_carga                  TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_dim_geografia_prefix ON dw.dim_geografia (zip_code_prefix);
CREATE INDEX idx_dim_geografia_uf ON dw.dim_geografia (estado);

COMMENT ON TABLE dw.dim_geografia IS 'Dimensão Geográfica consolidando CEPs, municípios, estados e coordenadas espaciais';
COMMENT ON COLUMN dw.dim_geografia.zip_code_prefix IS 'Prefixo de 5 dígitos do CEP (Chave Natural)';
COMMENT ON COLUMN dw.dim_geografia.latitude IS 'Latitude média consolidada do prefixo de CEP';
COMMENT ON COLUMN dw.dim_geografia.longitude IS 'Longitude média consolidada do prefixo de CEP';

-- ------------------------------------------------------------------------------
-- 2. Dimensão: dw.dim_cliente (SCD Tipo 2 com Outrigger Geográfica)
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS dw.dim_cliente CASCADE;

CREATE TABLE dw.dim_cliente (
    -- Chave Substituta (Surrogate Key)
    sk_cliente                  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,    
    -- Chaves de Negócio / Naturais e Linhagem
    nk_customer_unique_id       VARCHAR(32) NOT NULL,
    customer_id_origem          VARCHAR(32), -- ID do pedido que gerou esta versão cadastral    
    -- Vínculo Geográfico (Outrigger Dimension)
    sk_geografia                INT NOT NULL REFERENCES dw.dim_geografia (sk_geografia),
    customer_zip_code_prefix    VARCHAR(5) NOT NULL, -- Mantido para auditoria rápida    
    -- Metadados de Vigência SCD Tipo 2
    data_inicio                 TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    data_fim                    TIMESTAMP WITHOUT TIME ZONE, -- NULL indica registro ativo
    is_atual                    BOOLEAN NOT NULL DEFAULT TRUE,
    versao                      INT NOT NULL DEFAULT 1,    
    -- Auditoria de Carga
    data_carga                  TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_dim_cliente_nk ON dw.dim_cliente (nk_customer_unique_id);
CREATE INDEX idx_dim_cliente_atual ON dw.dim_cliente (nk_customer_unique_id) WHERE is_atual = TRUE;
CREATE INDEX idx_dim_cliente_geografia ON dw.dim_cliente (sk_geografia);

COMMENT ON TABLE dw.dim_cliente IS 'Dimensão de Clientes com versionamento histórico SCD Tipo 2 referenciando dim_geografia';
COMMENT ON COLUMN dw.dim_cliente.sk_cliente IS 'Surrogate Key artificial (INT) para relacionamentos com as Fatos';
COMMENT ON COLUMN dw.dim_cliente.is_atual IS 'Flag booleana indicando a foto cadastral mais recente';

-- ------------------------------------------------------------------------------
-- 3. Dimensão: dw.dim_vendedor (SCD Tipo 1 com Outrigger Geográfica)
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS dw.dim_vendedor CASCADE;

CREATE TABLE dw.dim_vendedor (
    -- Chave Substituta (Surrogate Key)
    sk_vendedor                 INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,    
    -- Chave de Negócio
    nk_seller_id                VARCHAR(32) NOT NULL UNIQUE,    
    -- Vínculo Geográfico (Outrigger Dimension)
    sk_geografia                INT NOT NULL REFERENCES dw.dim_geografia (sk_geografia),
    seller_zip_code_prefix      VARCHAR(5) NOT NULL, -- Mantido para auditoria rápida    
    -- Auditoria de Carga
    data_carga                  TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_dim_vendedor_nk ON dw.dim_vendedor (nk_seller_id);
CREATE INDEX idx_dim_vendedor_geografia ON dw.dim_vendedor (sk_geografia);

COMMENT ON TABLE dw.dim_vendedor IS 'Dimensão de Vendedores parceiros referenciando dim_geografia';

-- ------------------------------------------------------------------------------
-- 4. Dimensão: dw.dim_produto (Catálogo e Dimensões Físicas)
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS dw.dim_produto CASCADE;

CREATE TABLE dw.dim_produto (
    -- Chave Substituta (Surrogate Key)
    sk_produto                      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,    
    -- Chave de Negócio
    nk_product_id                   VARCHAR(32) NOT NULL UNIQUE,    
    -- Atributos Descritivos e Categoria Traduzida
    product_category_name           VARCHAR(100) NOT NULL DEFAULT 'Nao Informado',
    product_category_name_english   VARCHAR(100) NOT NULL DEFAULT 'Not Informed',
    product_name_length             INT,
    product_description_length      INT,
    product_photos_qty              INT,    
    -- Especificações Logísticas / Físicas
    product_weight_g                NUMERIC(10,2),
    product_length_cm               NUMERIC(10,2),
    product_height_cm               NUMERIC(10,2),
    product_width_cm                NUMERIC(10,2),
    product_volume_cm3              NUMERIC(12,2), -- Volume aproximado (length * height * width)    
    -- Auditoria de Carga
    data_carga                      TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_dim_produto_nk ON dw.dim_produto (nk_product_id);
CREATE INDEX idx_dim_produto_categoria ON dw.dim_produto (product_category_name);

COMMENT ON TABLE dw.dim_produto IS 'Dimensão de Produtos com categorias em português/inglês e métricas físicas';

-- ------------------------------------------------------------------------------
-- 5. Dimensão: dw.dim_calendario (Role-Playing Dimension)
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS dw.dim_calendario CASCADE;

CREATE TABLE dw.dim_calendario (
    -- Chave Substituta no formato YYYYMMDD (Padrão Canônico Kimball)
    sk_data                     INT PRIMARY KEY,    
    -- Data canônica
    data                        DATE NOT NULL UNIQUE,    
    -- Hierarquias Temporais
    ano                         INT NOT NULL,
    trimestre                   INT NOT NULL,
    ano_trimestre               VARCHAR(7) NOT NULL,  -- Ex: '2017-T1'
    mes                         INT NOT NULL,
    nome_mes                    VARCHAR(20) NOT NULL, -- Ex: 'Janeiro'
    nome_mes_abrev              VARCHAR(3) NOT NULL,  -- Ex: 'Jan'
    ano_mes                     VARCHAR(7) NOT NULL,  -- Ex: '2017-01'
    dia_mes                     INT NOT NULL,
    dia_semana                  INT NOT NULL,         -- 1 (Dom) a 7 (Sáb)
    nome_dia_semana             VARCHAR(20) NOT NULL, -- Ex: 'Segunda-feira'
    semana_ano                  INT NOT NULL,    
    -- Flags Analíticas
    is_fim_semana               BOOLEAN NOT NULL,
    is_dia_util                 BOOLEAN NOT NULL,
    semestre                    INT NOT NULL
);

CREATE INDEX idx_dim_calendario_data ON dw.dim_calendario (data);
CREATE INDEX idx_dim_calendario_ano_mes ON dw.dim_calendario (ano_mes);

COMMENT ON TABLE dw.dim_calendario IS 'Dimensão Calendário global para suporte a Role-Playing Dimensions e Time Intelligence';
