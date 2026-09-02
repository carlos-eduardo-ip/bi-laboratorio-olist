-- ==============================================================================
-- Script: 01_create_staging_tables.sql
-- Descrição: Criação das 9 tabelas da camada de staging no PostgreSQL
-- Filosofia: Permissiva (TEXT) para garantir 100% de tolerância na ingestão bruta (ELT)
-- Idempotência: DROP TABLE IF EXISTS para recriação limpa quando necessário
-- ==============================================================================

-- 1. Tabela: staging.orders (Ciclo de vida dos pedidos)
DROP TABLE IF EXISTS staging.orders CASCADE;
CREATE TABLE staging.orders (
    order_id                        TEXT,
    customer_id                     TEXT,
    order_status                    TEXT,
    order_purchase_timestamp        TEXT,
    order_approved_at               TEXT,
    order_delivered_carrier_date    TEXT,
    order_delivered_customer_date   TEXT,
    order_estimated_delivery_date   TEXT
);

-- 2. Tabela: staging.order_items (Itens de cada pedido)
DROP TABLE IF EXISTS staging.order_items CASCADE;
CREATE TABLE staging.order_items (
    order_id                        TEXT,
    order_item_id                   TEXT,
    product_id                      TEXT,
    seller_id                       TEXT,
    shipping_limit_date             TEXT,
    price                           TEXT,
    freight_value                   TEXT
);

-- 3. Tabela: staging.order_payments (Transações de pagamento)
DROP TABLE IF EXISTS staging.order_payments CASCADE;
CREATE TABLE staging.order_payments (
    order_id                        TEXT,
    payment_sequential              TEXT,
    payment_type                    TEXT,
    payment_installments            TEXT,
    payment_value                   TEXT
);

-- 4. Tabela: staging.order_reviews (Avaliações e satisfação / CSAT)
DROP TABLE IF EXISTS staging.order_reviews CASCADE;
CREATE TABLE staging.order_reviews (
    review_id                       TEXT,
    order_id                        TEXT,
    review_score                    TEXT,
    review_comment_title            TEXT,
    review_comment_message          TEXT,
    review_creation_date            TEXT,
    review_answer_timestamp         TEXT
);

-- 5. Tabela: staging.customers (Cadastro transacional e mestre de clientes)
DROP TABLE IF EXISTS staging.customers CASCADE;
CREATE TABLE staging.customers (
    customer_id                     TEXT,
    customer_unique_id              TEXT,
    customer_zip_code_prefix        TEXT,
    customer_city                   TEXT,
    customer_state                  TEXT
);

-- 6. Tabela: staging.sellers (Cadastro de vendedores parceiros)
DROP TABLE IF EXISTS staging.sellers CASCADE;
CREATE TABLE staging.sellers (
    seller_id                       TEXT,
    seller_zip_code_prefix          TEXT,
    seller_city                     TEXT,
    seller_state                    TEXT
);

-- 7. Tabela: staging.products (Catálogo de produtos e especificações físicas)
DROP TABLE IF EXISTS staging.products CASCADE;
CREATE TABLE staging.products (
    product_id                      TEXT,
    product_category_name           TEXT,
    product_name_lenght             TEXT,
    product_description_lenght      TEXT,
    product_photos_qty              TEXT,
    product_weight_g                TEXT,
    product_length_cm               TEXT,
    product_height_cm               TEXT,
    product_width_cm                TEXT
);

-- 8. Tabela: staging.geolocation (Coordenadas geográficas por prefixo de CEP)
DROP TABLE IF EXISTS staging.geolocation CASCADE;
CREATE TABLE staging.geolocation (
    geolocation_zip_code_prefix     TEXT,
    geolocation_lat                 TEXT,
    geolocation_lng                 TEXT,
    geolocation_city                TEXT,
    geolocation_state               TEXT
);

-- 9. Tabela: staging.product_category_name_translation (Lookup de tradução PT -> EN)
DROP TABLE IF EXISTS staging.product_category_name_translation CASCADE;
CREATE TABLE staging.product_category_name_translation (
    product_category_name           TEXT,
    product_category_name_english   TEXT
);
