-- ==============================================================================
-- Script: 02_create_dw_facts.sql
-- Descrição: Criação das Tabelas Fato do Data Warehouse (Kimball Fact Constellation)
-- Schema: dw
-- Decisões Aplicadas:
--   - Granularidade atômica para vendas: 1 linha por item do pedido (order_id + order_item_id)
--   - Fatos separadas para pagamentos e avaliações evitando fan traps / duplicações
--   - Surrogate Keys (FKs) apontando para as Dimensões Conformadas
--   - Degenerate Dimensions (order_id, review_id, status) mantidas nas fatos para rastreabilidade
--   - Integridade Referencial (FOREIGN KEYs) e Índices B-Tree em todas as FKs
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Tabela Fato: dw.fato_itens_pedido (Processo de Vendas e Logística)
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS dw.fato_itens_pedido CASCADE;

CREATE TABLE dw.fato_itens_pedido (
    -- Chave Primária da Fato
    sk_item_pedido                  INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,    
    -- Chaves Estrangeiras (Dimensões Conformadas)
    sk_cliente                      INT NOT NULL REFERENCES dw.dim_cliente (sk_cliente),
    sk_vendedor                     INT NOT NULL REFERENCES dw.dim_vendedor (sk_vendedor),
    sk_produto                      INT NOT NULL REFERENCES dw.dim_produto (sk_produto),    
    -- Role-Playing Dimensions (Datas do Ciclo de Vida do Pedido)
    sk_data_compra                  INT NOT NULL REFERENCES dw.dim_calendario (sk_data),
    sk_data_aprovacao               INT REFERENCES dw.dim_calendario (sk_data),
    sk_data_envio_transportadora    INT REFERENCES dw.dim_calendario (sk_data),
    sk_data_entrega_real            INT REFERENCES dw.dim_calendario (sk_data),
    sk_data_entrega_estimada        INT REFERENCES dw.dim_calendario (sk_data),    
    -- Dimensões Degeneradas (Identificadores operacionais sem dimensão própria)
    order_id                        VARCHAR(32) NOT NULL,
    order_item_id                   INT NOT NULL,
    order_status                    VARCHAR(20) NOT NULL,    
    -- Timestamps Brutos para auditoria de SLA
    shipping_limit_date             TIMESTAMP WITHOUT TIME ZONE,
    order_purchase_timestamp        TIMESTAMP WITHOUT TIME ZONE,
    order_delivered_customer_date   TIMESTAMP WITHOUT TIME ZONE,
    order_estimated_delivery_date   TIMESTAMP WITHOUT TIME ZONE,    
    -- Métricas / Fatos Numéricos
    quantidade                      INT NOT NULL DEFAULT 1,
    preco                           NUMERIC(10,2) NOT NULL,
    valor_frete                     NUMERIC(10,2) NOT NULL,
    valor_total                     NUMERIC(10,2) NOT NULL, -- preco + valor_frete    
    -- Métricas Derivadas de SLA e Eficiência Logística
    dias_lead_time_total            NUMERIC(6,2), -- Compra até entrega real
    dias_atraso_entrega             NUMERIC(6,2), -- Entrega real - Estimada (positivo = atrasado)
    is_atrasado                     BOOLEAN NOT NULL DEFAULT FALSE,    
    -- Auditoria
    data_carga                      TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Índices de Foreign Key para otimização de JOINs
CREATE INDEX idx_fato_itens_sk_cliente ON dw.fato_itens_pedido (sk_cliente);
CREATE INDEX idx_fato_itens_sk_vendedor ON dw.fato_itens_pedido (sk_vendedor);
CREATE INDEX idx_fato_itens_sk_produto ON dw.fato_itens_pedido (sk_produto);
CREATE INDEX idx_fato_itens_sk_data_compra ON dw.fato_itens_pedido (sk_data_compra);
CREATE INDEX idx_fato_itens_order_id ON dw.fato_itens_pedido (order_id);

COMMENT ON TABLE dw.fato_itens_pedido IS 'Tabela Fato atômica de vendas por item do pedido e SLAs logísticos';
COMMENT ON COLUMN dw.fato_itens_pedido.valor_total IS 'Fato aditiva calculada (preco + valor_frete)';
COMMENT ON COLUMN dw.fato_itens_pedido.is_atrasado IS 'Flag booleana indicando se a entrega ultrapassou a data estimada';

-- ------------------------------------------------------------------------------
-- 2. Tabela Fato: dw.fato_pagamentos (Processo Financeiro)
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS dw.fato_pagamentos CASCADE;

CREATE TABLE dw.fato_pagamentos (
    -- Chave Primária da Fato
    sk_pagamento                    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,    
    -- Chaves Estrangeiras
    sk_cliente                      INT NOT NULL REFERENCES dw.dim_cliente (sk_cliente),
    sk_data_compra                  INT NOT NULL REFERENCES dw.dim_calendario (sk_data),    
    -- Dimensões Degeneradas
    order_id                        VARCHAR(32) NOT NULL,
    payment_sequential              INT NOT NULL,
    payment_type                    VARCHAR(30) NOT NULL,    
    -- Métricas / Fatos Numéricos
    payment_installments            INT NOT NULL,
    payment_value                   NUMERIC(10,2) NOT NULL,    
    -- Auditoria
    data_carga                      TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_fato_pagamentos_sk_cliente ON dw.fato_pagamentos (sk_cliente);
CREATE INDEX idx_fato_pagamentos_sk_data ON dw.fato_pagamentos (sk_data_compra);
CREATE INDEX idx_fato_pagamentos_order_id ON dw.fato_pagamentos (order_id);

COMMENT ON TABLE dw.fato_pagamentos IS 'Tabela Fato de transações de pagamento por parcela e meio de pagamento';

-- ------------------------------------------------------------------------------
-- 3. Tabela Fato: dw.fato_avaliacoes (Processo de Satisfação do Cliente / CSAT)
-- ------------------------------------------------------------------------------
DROP TABLE IF EXISTS dw.fato_avaliacoes CASCADE;

CREATE TABLE dw.fato_avaliacoes (
    -- Chave Primária da Fato
    sk_avaliacao                    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,    
    -- Chaves Estrangeiras
    sk_cliente                      INT NOT NULL REFERENCES dw.dim_cliente (sk_cliente),
    sk_data_criacao                 INT NOT NULL REFERENCES dw.dim_calendario (sk_data),
    sk_data_resposta                INT REFERENCES dw.dim_calendario (sk_data),    
    -- Dimensões Degeneradas
    order_id                        VARCHAR(32) NOT NULL,
    review_id                       VARCHAR(32) NOT NULL,    
    -- Fatos e Scores
    review_score                    INT NOT NULL,    
    -- Flags e Métricas Textuais
    tem_comentario_titulo           BOOLEAN NOT NULL DEFAULT FALSE,
    tem_comentario_mensagem         BOOLEAN NOT NULL DEFAULT FALSE,
    review_comment_title            TEXT,
    review_comment_message          TEXT,
    tempo_resposta_horas            NUMERIC(8,2),    
    -- Auditoria
    data_carga                      TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_fato_avaliacoes_sk_cliente ON dw.fato_avaliacoes (sk_cliente);
CREATE INDEX idx_fato_avaliacoes_sk_data ON dw.fato_avaliacoes (sk_data_criacao);
CREATE INDEX idx_fato_avaliacoes_order_id ON dw.fato_avaliacoes (order_id);

COMMENT ON TABLE dw.fato_avaliacoes IS 'Tabela Fato de avaliações de clientes (CSAT) e tempo de resposta';
