-- ==============================================================================
-- Script: 03_populate_dw_dimensions.sql
-- Descrição: Pipeline Completo de Povoamento e Transformação ELT das Dimensões do DW
-- Schema: dw
-- Ordem de Carga (Respeitando Integridade Referencial):
--   1. dw.dim_calendario  (Independente: 2016 a 2019 + Sentinela -1)
--   2. dw.dim_geografia   (Independente: 19.015 CEPs consolidados + Sentinela -1)
--   3. dw.dim_vendedor    (Depende de dim_geografia + Sentinela -1)
--   4. dw.dim_produto     (Independente: catálogo tratado + cubagem + Sentinela -1)
--   5. dw.dim_cliente     (Depende de dim_geografia + SCD Tipo 2 + Sentinela -1)
-- ==============================================================================

-- ==============================================================================
-- 1. POVOAMENTO: dw.dim_calendario
-- ==============================================================================
TRUNCATE TABLE dw.dim_calendario CASCADE;

-- 1.1 Registro Sentinela (-1)
INSERT INTO dw.dim_calendario (
    sk_data, data, ano, trimestre, ano_trimestre, mes, nome_mes, nome_mes_abrev,
    ano_mes, dia_mes, dia_semana, nome_dia_semana, semana_ano, is_fim_semana, is_dia_util, semestre
) VALUES (
    -1, '1900-01-01'::DATE, 1900, 0, 'N/A', 0, 'Nao Aplicavel', 'N/A',
    'N/A', 0, 0, 'Nao Aplicavel', 0, FALSE, FALSE, 0
);

-- 1.2 Carga Contínua (2016 a 2019)
INSERT INTO dw.dim_calendario (
    sk_data, data, ano, trimestre, ano_trimestre, mes, nome_mes, nome_mes_abrev,
    ano_mes, dia_mes, dia_semana, nome_dia_semana, semana_ano, is_fim_semana, is_dia_util, semestre
)
WITH datas_geradas AS (
    SELECT generate_series('2016-01-01'::DATE, '2019-12-31'::DATE, INTERVAL '1 day')::DATE AS d
)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT                                AS sk_data,
    d                                                          AS data,
    EXTRACT(YEAR FROM d)::INT                                  AS ano,
    EXTRACT(QUARTER FROM d)::INT                               AS trimestre,
    TO_CHAR(d, 'YYYY') || '-T' || EXTRACT(QUARTER FROM d)::TEXT AS ano_trimestre,
    EXTRACT(MONTH FROM d)::INT                                 AS mes,
    CASE EXTRACT(MONTH FROM d)::INT
        WHEN 1  THEN 'Janeiro'   WHEN 2  THEN 'Fevereiro'
        WHEN 3  THEN 'Março'     WHEN 4  THEN 'Abril'
        WHEN 5  THEN 'Maio'      WHEN 6  THEN 'Junho'
        WHEN 7  THEN 'Julho'     WHEN 8  THEN 'Agosto'
        WHEN 9  THEN 'Setembro'  WHEN 10 THEN 'Outubro'
        WHEN 11 THEN 'Novembro'  WHEN 12 THEN 'Dezembro'
    END                                                        AS nome_mes,
    CASE EXTRACT(MONTH FROM d)::INT
        WHEN 1  THEN 'Jan' WHEN 2  THEN 'Fev' WHEN 3  THEN 'Mar'
        WHEN 4  THEN 'Abr' WHEN 5  THEN 'Mai' WHEN 6  THEN 'Jun'
        WHEN 7  THEN 'Jul' WHEN 8  THEN 'Ago' WHEN 9  THEN 'Set'
        WHEN 10 THEN 'Out' WHEN 11 THEN 'Nov' WHEN 12 THEN 'Dez'
    END                                                        AS nome_mes_abrev,
    TO_CHAR(d, 'YYYY-MM')                                      AS ano_mes,
    EXTRACT(DAY FROM d)::INT                                   AS dia_mes,
    EXTRACT(ISODOW FROM d)::INT                                AS dia_semana,
    CASE EXTRACT(ISODOW FROM d)::INT
        WHEN 1 THEN 'Segunda-feira' WHEN 2 THEN 'Terça-feira'  WHEN 3 THEN 'Quarta-feira'
        WHEN 4 THEN 'Quinta-feira'  WHEN 5 THEN 'Sexta-feira'  WHEN 6 THEN 'Sábado'
        WHEN 7 THEN 'Domingo'
    END                                                        AS nome_dia_semana,
    EXTRACT(WEEK FROM d)::INT                                  AS semana_ano,
    (EXTRACT(ISODOW FROM d)::INT IN (6, 7))                    AS is_fim_semana,
    (EXTRACT(ISODOW FROM d)::INT NOT IN (6, 7))                AS is_dia_util,
    CASE WHEN EXTRACT(MONTH FROM d) <= 6 THEN 1 ELSE 2 END     AS semestre
FROM datas_geradas;


-- ==============================================================================
-- 2. POVOAMENTO: dw.dim_geografia
-- ==============================================================================
TRUNCATE TABLE dw.dim_geografia CASCADE;

-- 2.1 Registro Sentinela (-1)
INSERT INTO dw.dim_geografia (
    sk_geografia, zip_code_prefix, cidade, estado, regiao, latitude, longitude
) OVERRIDING SYSTEM VALUE VALUES (
    -1, '00000', 'Nao Informado', 'ND', 'Nao Informado', NULL, NULL
);

-- 2.2 Carga de CEPs consolidados por Mediana e Moda
INSERT INTO dw.dim_geografia (
    zip_code_prefix, cidade, estado, regiao, latitude, longitude
)
WITH geo_limpa AS (
    SELECT
        LPAD(TRIM(geolocation_zip_code_prefix), 5, '0') AS zip_code_prefix,
        INITCAP(TRIM(geolocation_city))                 AS cidade,
        UPPER(TRIM(geolocation_state))                  AS estado,
        geolocation_lat::NUMERIC                        AS lat,
        geolocation_lng::NUMERIC                        AS lng
    FROM staging.geolocation
    WHERE geolocation_zip_code_prefix IS NOT NULL
),
geo_coords AS (
    SELECT
        zip_code_prefix,
        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY lat)::NUMERIC, 6) AS latitude,
        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY lng)::NUMERIC, 6) AS longitude
    FROM geo_limpa
    GROUP BY zip_code_prefix
),
geo_names_ranked AS (
    SELECT
        zip_code_prefix,
        cidade,
        estado,
        ROW_NUMBER() OVER (
            PARTITION BY zip_code_prefix 
            ORDER BY COUNT(*) DESC, cidade ASC
        ) AS rnk
    FROM geo_limpa
    GROUP BY zip_code_prefix, cidade, estado
)
SELECT
    c.zip_code_prefix,
    n.cidade,
    n.estado,
    CASE n.estado
        WHEN 'SP' THEN 'Sudeste'      WHEN 'RJ' THEN 'Sudeste'
        WHEN 'MG' THEN 'Sudeste'      WHEN 'ES' THEN 'Sudeste'
        WHEN 'PR' THEN 'Sul'          WHEN 'SC' THEN 'Sul'
        WHEN 'RS' THEN 'Sul'          WHEN 'DF' THEN 'Centro-Oeste'
        WHEN 'GO' THEN 'Centro-Oeste' WHEN 'MT' THEN 'Centro-Oeste'
        WHEN 'MS' THEN 'Centro-Oeste' WHEN 'BA' THEN 'Nordeste'
        WHEN 'PE' THEN 'Nordeste'     WHEN 'CE' THEN 'Nordeste'
        WHEN 'MA' THEN 'Nordeste'     WHEN 'PB' THEN 'Nordeste'
        WHEN 'RN' THEN 'Nordeste'     WHEN 'AL' THEN 'Nordeste'
        WHEN 'PI' THEN 'Nordeste'     WHEN 'SE' THEN 'Nordeste'
        WHEN 'AM' THEN 'Norte'        WHEN 'PA' THEN 'Norte'
        WHEN 'RO' THEN 'Norte'        WHEN 'TO' THEN 'Norte'
        WHEN 'AC' THEN 'Norte'        WHEN 'AP' THEN 'Norte'
        WHEN 'RR' THEN 'Norte'
        ELSE 'Nao Informado'
    END AS regiao,
    c.latitude,
    c.longitude
FROM geo_coords c
JOIN geo_names_ranked n 
  ON c.zip_code_prefix = n.zip_code_prefix
WHERE n.rnk = 1
ORDER BY c.zip_code_prefix;


-- ==============================================================================
-- 3. POVOAMENTO: dw.dim_vendedor
-- ==============================================================================
TRUNCATE TABLE dw.dim_vendedor CASCADE;

-- 3.1 Registro Sentinela (-1)
INSERT INTO dw.dim_vendedor (
    sk_vendedor, nk_seller_id, sk_geografia, seller_zip_code_prefix
) OVERRIDING SYSTEM VALUE VALUES (
    -1, 'DESCONHECIDO', -1, '00000'
);

-- 3.2 Carga de Vendedores com Lookup em dim_geografia via COALESCE
INSERT INTO dw.dim_vendedor (
    nk_seller_id, sk_geografia, seller_zip_code_prefix
)
SELECT
    s.seller_id                                         AS nk_seller_id,
    COALESCE(g.sk_geografia, -1)                        AS sk_geografia,
    LPAD(TRIM(s.seller_zip_code_prefix), 5, '0')        AS seller_zip_code_prefix
FROM staging.sellers s
LEFT JOIN dw.dim_geografia g 
  ON LPAD(TRIM(s.seller_zip_code_prefix), 5, '0') = g.zip_code_prefix
ORDER BY s.seller_id;


-- ==============================================================================
-- 4. POVOAMENTO: dw.dim_produto
-- ==============================================================================
TRUNCATE TABLE dw.dim_produto CASCADE;

-- 4.1 Registro Sentinela (-1)
INSERT INTO dw.dim_produto (
    sk_produto, nk_product_id, product_category_name, product_category_name_english,
    product_name_length, product_description_length, product_photos_qty,
    product_weight_g, product_length_cm, product_height_cm, product_width_cm, product_volume_cm3
) OVERRIDING SYSTEM VALUE VALUES (
    -1, 'DESCONHECIDO', 'Nao Informado', 'Not Informed',
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
);

-- 4.2 Carga de Produtos com Tratamento de Nulos, Tradução e Cubagem Logística
INSERT INTO dw.dim_produto (
    nk_product_id,
    product_category_name,
    product_category_name_english,
    product_name_length,
    product_description_length,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm,
    product_volume_cm3
)
SELECT
    p.product_id                                        AS nk_product_id,
    COALESCE(NULLIF(TRIM(p.product_category_name), ''), 'Nao Informado') AS product_category_name,
    COALESCE(NULLIF(TRIM(t.product_category_name_english), ''), 'Not Informed') AS product_category_name_english,
    p.product_name_lenght::INT                          AS product_name_length,
    p.product_description_lenght::INT                   AS product_description_length,
    p.product_photos_qty::INT                           AS product_photos_qty,
    p.product_weight_g::NUMERIC(10,2)                   AS product_weight_g,
    p.product_length_cm::NUMERIC(10,2)                  AS product_length_cm,
    p.product_height_cm::NUMERIC(10,2)                  AS product_height_cm,
    p.product_width_cm::NUMERIC(10,2)                   AS product_width_cm,
    -- Cubagem Logística: C x L x A em cm3
    CASE 
        WHEN p.product_length_cm::NUMERIC IS NOT NULL 
         AND p.product_height_cm::NUMERIC IS NOT NULL 
         AND p.product_width_cm::NUMERIC IS NOT NULL 
        THEN ROUND((p.product_length_cm::NUMERIC * p.product_height_cm::NUMERIC * p.product_width_cm::NUMERIC), 2)
        ELSE NULL 
    END                                                 AS product_volume_cm3
FROM staging.products p
LEFT JOIN staging.product_category_name_translation t 
  ON TRIM(p.product_category_name) = TRIM(t.product_category_name)
ORDER BY p.product_id;


-- ==============================================================================
-- 5. POVOAMENTO: dw.dim_cliente (SCD Tipo 2 com Window Functions)
-- ==============================================================================
TRUNCATE TABLE dw.dim_cliente CASCADE;

-- 5.1 Registro Sentinela (-1)
INSERT INTO dw.dim_cliente (
    sk_cliente, nk_customer_unique_id, customer_id_origem, sk_geografia,
    customer_zip_code_prefix, data_inicio, data_fim, is_atual, versao
) OVERRIDING SYSTEM VALUE VALUES (
    -1, 'DESCONHECIDO', 'N/A', -1, '00000', '1900-01-01 00:00:00'::TIMESTAMP, NULL, TRUE, 1
);

-- 5.2 Carga de Clientes com Versionamento Histórico de Endereço (SCD Tipo 2)
INSERT INTO dw.dim_cliente (
    nk_customer_unique_id,
    customer_id_origem,
    sk_geografia,
    customer_zip_code_prefix,
    data_inicio,
    data_fim,
    is_atual,
    versao
)
WITH compras_cliente AS (
    -- Vincula cada compra com a data real da transação
    SELECT
        c.customer_unique_id,
        c.customer_id,
        LPAD(TRIM(c.customer_zip_code_prefix), 5, '0') AS zip_prefix,
        COALESCE(o.order_purchase_timestamp::TIMESTAMP, '2016-01-01 00:00:00'::TIMESTAMP) AS data_compra
    FROM staging.customers c
    LEFT JOIN staging.orders o 
      ON c.customer_id = o.customer_id
),
enderecos_agrupados AS (
    -- Detecta a data da primeira compra em cada endereço do cliente
    SELECT
        customer_unique_id,
        zip_prefix,
        -- Pega um customer_id representativo para linhagem
        MIN(customer_id) AS customer_id_origem,
        MIN(data_compra) AS data_inicio
    FROM compras_cliente
    GROUP BY customer_unique_id, zip_prefix
),
historico_scd2 AS (
    -- Calcula vigência (data_fim, is_atual e versao) usando LEAD e ROW_NUMBER
    SELECT
        e.customer_unique_id,
        e.customer_id_origem,
        e.zip_prefix,
        e.data_inicio,
        LEAD(e.data_inicio) OVER (
            PARTITION BY e.customer_unique_id 
            ORDER BY e.data_inicio ASC
        ) AS proxima_data,
        ROW_NUMBER() OVER (
            PARTITION BY e.customer_unique_id 
            ORDER BY e.data_inicio ASC
        ) AS versao
    FROM enderecos_agrupados e
)
SELECT
    h.customer_unique_id                                AS nk_customer_unique_id,
    h.customer_id_origem,
    COALESCE(g.sk_geografia, -1)                        AS sk_geografia,
    h.zip_prefix                                        AS customer_zip_code_prefix,
    h.data_inicio,
    h.proxima_data                                      AS data_fim,
    (h.proxima_data IS NULL)                            AS is_atual,
    h.versao
FROM historico_scd2 h
LEFT JOIN dw.dim_geografia g 
  ON h.zip_prefix = g.zip_code_prefix
ORDER BY h.customer_unique_id, h.versao;


-- ==============================================================================
-- 6. AUDITORIA CONSOLIDADA DAS DIMENSÕES
-- ==============================================================================
DO $$
DECLARE
    v_total_cal INT;
    v_total_geo INT;
    v_total_ven INT;
    v_total_prd INT;
    v_total_cli INT;
    v_cli_atuais INT;
    v_cli_historicos INT;
BEGIN
    SELECT COUNT(*) INTO v_total_cal FROM dw.dim_calendario;
    SELECT COUNT(*) INTO v_total_geo FROM dw.dim_geografia;
    SELECT COUNT(*) INTO v_total_ven FROM dw.dim_vendedor;
    SELECT COUNT(*) INTO v_total_prd FROM dw.dim_produto;
    SELECT COUNT(*) INTO v_total_cli FROM dw.dim_cliente;
    SELECT COUNT(*) INTO v_cli_atuais FROM dw.dim_cliente WHERE is_atual = TRUE;
    SELECT COUNT(*) INTO v_cli_historicos FROM dw.dim_cliente WHERE is_atual = FALSE;

    RAISE NOTICE '=============================================================';
    RAISE NOTICE 'AUDITORIA GERAL DE POVOAMENTO DAS DIMENSÕES DO DW:';
    RAISE NOTICE '1. dw.dim_calendario: % linhas', v_total_cal;
    RAISE NOTICE '2. dw.dim_geografia:  % linhas', v_total_geo;
    RAISE NOTICE '3. dw.dim_vendedor:   % linhas', v_total_ven;
    RAISE NOTICE '4. dw.dim_produto:    % linhas', v_total_prd;
    RAISE NOTICE '5. dw.dim_cliente:    % linhas (Atuais: % | Históricos: %)', v_total_cli, v_cli_atuais, v_cli_historicos;
    RAISE NOTICE '=============================================================';
END $$;
