-- ==============================================================================
-- Script: 02_validate_staging.sql
-- Descrição: Validação e auditoria pós-carga da camada de staging
-- Executa a contagem de registros e compara com o volume esperado dos CSVs
-- Converme validado anteriormente para o formato de tabela de auditoria
-- ==============================================================================

SELECT 
    'staging.orders' AS tabela,
    COUNT(*) AS total_linhas_carregadas,
    99441 AS volume_esperado_csv,
    CASE WHEN COUNT(*) = 99441 THEN 'OK ✅' ELSE 'DIVERGÊNCIA ⚠️' END AS status
FROM staging.orders

UNION ALL

SELECT 
    'staging.order_items' AS tabela,
    COUNT(*) AS total_linhas_carregadas,
    112650 AS volume_esperado_csv,
    CASE WHEN COUNT(*) = 112650 THEN 'OK ✅' ELSE 'DIVERGÊNCIA ⚠️' END AS status
FROM staging.order_items

UNION ALL

SELECT 
    'staging.order_payments' AS tabela,
    COUNT(*) AS total_linhas_carregadas,
    103886 AS volume_esperado_csv,
    CASE WHEN COUNT(*) = 103886 THEN 'OK ✅' ELSE 'DIVERGÊNCIA ⚠️' END AS status
FROM staging.order_payments

UNION ALL

SELECT 
    'staging.order_reviews' AS tabela,
    COUNT(*) AS total_linhas_carregadas,
    99224 AS volume_esperado_csv,
    CASE WHEN COUNT(*) = 99224 THEN 'OK ✅' ELSE 'DIVERGÊNCIA ⚠️' END AS status
FROM staging.order_reviews

UNION ALL

SELECT 
    'staging.customers' AS tabela,
    COUNT(*) AS total_linhas_carregadas,
    99441 AS volume_esperado_csv,
    CASE WHEN COUNT(*) = 99441 THEN 'OK ✅' ELSE 'DIVERGÊNCIA ⚠️' END AS status
FROM staging.customers

UNION ALL

SELECT 
    'staging.sellers' AS tabela,
    COUNT(*) AS total_linhas_carregadas,
    3095 AS volume_esperado_csv,
    CASE WHEN COUNT(*) = 3095 THEN 'OK ✅' ELSE 'DIVERGÊNCIA ⚠️' END AS status
FROM staging.sellers

UNION ALL

SELECT 
    'staging.products' AS tabela,
    COUNT(*) AS total_linhas_carregadas,
    32951 AS volume_esperado_csv,
    CASE WHEN COUNT(*) = 32951 THEN 'OK ✅' ELSE 'DIVERGÊNCIA ⚠️' END AS status
FROM staging.products

UNION ALL

SELECT 
    'staging.geolocation' AS tabela,
    COUNT(*) AS total_linhas_carregadas,
    1000163 AS volume_esperado_csv,
    CASE WHEN COUNT(*) = 1000163 THEN 'OK ✅' ELSE 'DIVERGÊNCIA ⚠️' END AS status
FROM staging.geolocation

UNION ALL

SELECT 
    'staging.product_category_name_translation' AS tabela,
    COUNT(*) AS total_linhas_carregadas,
    71 AS volume_esperado_csv,
    CASE WHEN COUNT(*) = 71 THEN 'OK ✅' ELSE 'DIVERGÊNCIA ⚠️' END AS status
FROM staging.product_category_name_translation

ORDER BY tabela;
