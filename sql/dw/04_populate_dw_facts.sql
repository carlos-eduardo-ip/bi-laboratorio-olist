-- ==============================================================================
-- Script: 04_populate_dw_facts.sql
-- Descrição: Carga e Povoamento ELT das Tabelas Fato do Data Warehouse
-- Schema: dw
-- Tabelas Fato:
--   1. dw.fato_itens_pedido (Granularidade: 1 linha por item de pedido)
--   2. dw.fato_pagamentos   (Granularidade: 1 linha por parcela/meio de pagamento)
--   3. dw.fato_avaliacoes   (Granularidade: 1 linha por review de cliente)
-- ==============================================================================

-- ==============================================================================
-- 1. POVOAMENTO: dw.fato_itens_pedido
-- ==============================================================================
TRUNCATE TABLE dw.fato_itens_pedido CASCADE;

INSERT INTO dw.fato_itens_pedido (
    sk_cliente,
    sk_vendedor,
    sk_produto,
    sk_data_compra,
    sk_data_aprovacao,
    sk_data_envio_transportadora,
    sk_data_entrega_real,
    sk_data_entrega_estimada,
    order_id,
    order_item_id,
    order_status,
    shipping_limit_date,
    order_purchase_timestamp,
    order_delivered_customer_date,
    order_estimated_delivery_date,
    quantidade,
    preco,
    valor_frete,
    valor_total,
    dias_lead_time_total,
    dias_atraso_entrega,
    is_atrasado
)
SELECT
    -- 1. Lookup Temporal do SCD Tipo 2 na dim_cliente
    COALESCE(c.sk_cliente, -1)                                  AS sk_cliente,    
    -- 2. Lookups Diretos de Vendedor e Produto
    COALESCE(v.sk_vendedor, -1)                                 AS sk_vendedor,
    COALESCE(p.sk_produto, -1)                                  AS sk_produto,    
    -- 3. Role-Playing Dimensions de Data (com Sentinela -1 para nulos)
    COALESCE(TO_CHAR(o.order_purchase_timestamp::TIMESTAMP, 'YYYYMMDD')::INT, -1)         AS sk_data_compra,
    COALESCE(TO_CHAR(o.order_approved_at::TIMESTAMP, 'YYYYMMDD')::INT, -1)                AS sk_data_aprovacao,
    COALESCE(TO_CHAR(o.order_delivered_carrier_date::TIMESTAMP, 'YYYYMMDD')::INT, -1)     AS sk_data_envio_transportadora,
    COALESCE(TO_CHAR(o.order_delivered_customer_date::TIMESTAMP, 'YYYYMMDD')::INT, -1)    AS sk_data_entrega_real,
    COALESCE(TO_CHAR(o.order_estimated_delivery_date::TIMESTAMP, 'YYYYMMDD')::INT, -1)    AS sk_data_entrega_estimada,    
    -- 4. Dimensões Degeneradas
    oi.order_id,
    oi.order_item_id::INT                                       AS order_item_id,
    o.order_status,    
    -- 5. Timestamps de Auditoria Operacional
    oi.shipping_limit_date::TIMESTAMP                           AS shipping_limit_date,
    o.order_purchase_timestamp::TIMESTAMP                       AS order_purchase_timestamp,
    o.order_delivered_customer_date::TIMESTAMP                  AS order_delivered_customer_date,
    o.order_estimated_delivery_date::TIMESTAMP                  AS order_estimated_delivery_date,    
    -- 6. Fatos Aditivas
    1                                                           AS quantidade,
    oi.price::NUMERIC(10,2)                                     AS preco,
    oi.freight_value::NUMERIC(10,2)                             AS valor_frete,
    (oi.price::NUMERIC(10,2) + oi.freight_value::NUMERIC(10,2)) AS valor_total,    
    -- 7. Métricas de SLA via EXTRACT(EPOCH) / 86400.0 (em dias decimais)
    CASE 
        WHEN o.order_delivered_customer_date IS NOT NULL AND o.order_purchase_timestamp IS NOT NULL
        THEN ROUND((EXTRACT(EPOCH FROM (o.order_delivered_customer_date::TIMESTAMP - o.order_purchase_timestamp::TIMESTAMP)) / 86400.0)::NUMERIC, 2)
        ELSE NULL 
    END                                                         AS dias_lead_time_total,
    CASE 
        WHEN o.order_delivered_customer_date IS NOT NULL AND o.order_estimated_delivery_date IS NOT NULL
        THEN ROUND((EXTRACT(EPOCH FROM (o.order_delivered_customer_date::TIMESTAMP - o.order_estimated_delivery_date::TIMESTAMP)) / 86400.0)::NUMERIC, 2)
        ELSE NULL 
    END                                                         AS dias_atraso_entrega,
    -- Flag de Atraso
    CASE 
        WHEN o.order_delivered_customer_date IS NOT NULL AND o.order_estimated_delivery_date IS NOT NULL
        THEN (o.order_delivered_customer_date::TIMESTAMP > o.order_estimated_delivery_date::TIMESTAMP)
        ELSE FALSE
    END                                                         AS is_atrasado
FROM staging.order_items oi
JOIN staging.orders o 
  ON oi.order_id = o.order_id
-- Vinculação com o cliente original da transação
LEFT JOIN staging.customers sc 
  ON o.customer_id = sc.customer_id
-- Encaixe temporal perfeito com o SCD Tipo 2
LEFT JOIN dw.dim_cliente c 
  ON sc.customer_unique_id = c.nk_customer_unique_id
 AND o.order_purchase_timestamp::TIMESTAMP >= c.data_inicio
 AND (c.data_fim IS NULL OR o.order_purchase_timestamp::TIMESTAMP < c.data_fim)
LEFT JOIN dw.dim_vendedor v 
  ON oi.seller_id = v.nk_seller_id
LEFT JOIN dw.dim_produto p 
  ON oi.product_id = p.nk_product_id;


-- ==============================================================================
-- 2. POVOAMENTO: dw.fato_pagamentos
-- ==============================================================================
TRUNCATE TABLE dw.fato_pagamentos CASCADE;

INSERT INTO dw.fato_pagamentos (
    sk_cliente,
    sk_data_compra,
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
)
SELECT
    COALESCE(c.sk_cliente, -1)                                  AS sk_cliente,
    COALESCE(TO_CHAR(o.order_purchase_timestamp::TIMESTAMP, 'YYYYMMDD')::INT, -1) AS sk_data_compra,
    op.order_id,
    op.payment_sequential::INT                                  AS payment_sequential,
    op.payment_type,
    op.payment_installments::INT                                AS payment_installments,
    op.payment_value::NUMERIC(10,2)                             AS payment_value
FROM staging.order_payments op
JOIN staging.orders o 
  ON op.order_id = o.order_id
LEFT JOIN staging.customers sc 
  ON o.customer_id = sc.customer_id
LEFT JOIN dw.dim_cliente c 
  ON sc.customer_unique_id = c.nk_customer_unique_id
 AND o.order_purchase_timestamp::TIMESTAMP >= c.data_inicio
 AND (c.data_fim IS NULL OR o.order_purchase_timestamp::TIMESTAMP < c.data_fim);


-- ==============================================================================
-- 3. POVOAMENTO: dw.fato_avaliacoes
-- ==============================================================================
TRUNCATE TABLE dw.fato_avaliacoes CASCADE;

INSERT INTO dw.fato_avaliacoes (
    sk_cliente,
    sk_data_criacao,
    sk_data_resposta,
    order_id,
    review_id,
    review_score,
    tem_comentario_titulo,
    tem_comentario_mensagem,
    review_comment_title,
    review_comment_message,
    tempo_resposta_horas
)
SELECT
    COALESCE(c.sk_cliente, -1)                                  AS sk_cliente,
    COALESCE(TO_CHAR(r.review_creation_date::TIMESTAMP, 'YYYYMMDD')::INT, -1)      AS sk_data_criacao,
    COALESCE(TO_CHAR(r.review_answer_timestamp::TIMESTAMP, 'YYYYMMDD')::INT, -1)    AS sk_data_resposta,
    r.order_id,
    r.review_id,
    r.review_score::INT                                         AS review_score,
    (r.review_comment_title IS NOT NULL AND TRIM(r.review_comment_title) <> '')     AS tem_comentario_titulo,
    (r.review_comment_message IS NOT NULL AND TRIM(r.review_comment_message) <> '') AS tem_comentario_mensagem,
    NULLIF(TRIM(r.review_comment_title), '')                    AS review_comment_title,
    NULLIF(TRIM(r.review_comment_message), '')                  AS review_comment_message,
    -- Tempo de resposta do cliente à pesquisa em horas
    CASE 
        WHEN r.review_answer_timestamp IS NOT NULL AND r.review_creation_date IS NOT NULL
        THEN ROUND((EXTRACT(EPOCH FROM (r.review_answer_timestamp::TIMESTAMP - r.review_creation_date::TIMESTAMP)) / 3600.0)::NUMERIC, 2)
        ELSE NULL 
    END                                                         AS tempo_resposta_horas
FROM staging.order_reviews r
JOIN staging.orders o 
  ON r.order_id = o.order_id
LEFT JOIN staging.customers sc 
  ON o.customer_id = sc.customer_id
LEFT JOIN dw.dim_cliente c 
  ON sc.customer_unique_id = c.nk_customer_unique_id
 AND o.order_purchase_timestamp::TIMESTAMP >= c.data_inicio
 AND (c.data_fim IS NULL OR o.order_purchase_timestamp::TIMESTAMP < c.data_fim);


-- ==============================================================================
-- 4. RELATÓRIO DE AUDITORIA E CONCILIAÇÃO DAS FATOS
-- ==============================================================================
DO $$
DECLARE
    v_itens_fato INT;
    v_itens_stg INT;
    v_pag_fato INT;
    v_pag_stg INT;
    v_aval_fato INT;
    v_aval_stg INT;
    v_receita_itens NUMERIC;
    v_receita_pag NUMERIC;
    v_clientes_orfaos INT;
BEGIN
    SELECT COUNT(*) INTO v_itens_fato FROM dw.fato_itens_pedido;
    SELECT COUNT(*) INTO v_itens_stg  FROM staging.order_items;
    
    SELECT COUNT(*) INTO v_pag_fato FROM dw.fato_pagamentos;
    SELECT COUNT(*) INTO v_pag_stg  FROM staging.order_payments;
    
    SELECT COUNT(*) INTO v_aval_fato FROM dw.fato_avaliacoes;
    SELECT COUNT(*) INTO v_aval_stg  FROM staging.order_reviews;
    
    SELECT ROUND(SUM(valor_total), 2) INTO v_receita_itens FROM dw.fato_itens_pedido;
    SELECT ROUND(SUM(payment_value), 2) INTO v_receita_pag FROM dw.fato_pagamentos;
    
    SELECT COUNT(*) INTO v_clientes_orfaos FROM dw.fato_itens_pedido WHERE sk_cliente = -1;

    RAISE NOTICE '=============================================================';
    RAISE NOTICE 'RELATÓRIO DE CONCILIAÇÃO E AUDITORIA DAS FATOS DO DW:';
    RAISE NOTICE '1. fato_itens_pedido: % linhas (Staging: %) | Órfãos: %', v_itens_fato, v_itens_stg, v_clientes_orfaos;
    RAISE NOTICE '2. fato_pagamentos:   % linhas (Staging: %)', v_pag_fato, v_pag_stg;
    RAISE NOTICE '3. fato_avaliacoes:   % linhas (Staging: %)', v_aval_fato, v_aval_stg;
    RAISE NOTICE '-------------------------------------------------------------';
    RAISE NOTICE 'CONCILIAÇÃO FINANCEIRA GLOBAL:';
    RAISE NOTICE 'Receita Total Itens (Preço + Frete): R$ %', v_receita_itens;
    RAISE NOTICE 'Receita Total Pagamentos Recebidos:  R$ %', v_receita_pag;
    RAISE NOTICE '=============================================================';
END $$;
