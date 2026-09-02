-- ==============================================================================
-- Script: 01_create_schemas.sql
-- Descrição: Criação dos schemas de governança e isolamento de camadas no PostgreSQL
-- Camadas:
--   - staging: Área de pouso dos dados brutos (Raw/Bronze)
--   - dw: Camada analítica dimensional com fatos e dimensões (Gold/Semantic)
-- ==============================================================================

-- 1. Schema para a Camada de Staging (Pouso de Dados Brutos)
CREATE SCHEMA IF NOT EXISTS staging;

-- 2. Schema para o Data Warehouse (Modelagem Dimensional - Kimball)
CREATE SCHEMA IF NOT EXISTS dw;

COMMENT ON SCHEMA staging IS 'Área de pouso transitória para ingestão de dados brutos da Olist sem restrições estritas.';
COMMENT ON SCHEMA dw IS 'Área analítica contendo tabelas fato, dimensões e visões de negócio consolidadas.';