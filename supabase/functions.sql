-- =====================================================================
-- Funções RPC do Supabase usadas pelo app de Inventário
-- =====================================================================
-- Este arquivo documenta/versiona as funções criadas diretamente no
-- SQL Editor do Supabase (não fazem parte do schema migrado
-- automaticamente). Sempre que alterar uma função lá, atualize aqui
-- também para manter o histórico no Git.
-- =====================================================================

-- ---------------------------------------------------------------------
-- increment_counting
-- ---------------------------------------------------------------------
-- Registra uma leitura de código de barras:
--   - Se já existe uma linha para (setor_id, codigo_barras), apenas
--     incrementa a quantidade em 1 (UPSERT atômico via ON CONFLICT).
--   - Se não existe, cria uma nova linha com quantidade 1, buscando
--     SKU/descrição na tabela product_db (se o código estiver
--     cadastrado) e marcando nao_cadastrado = true quando não estiver.
--
-- Corrigido em 02/10/2026: a versão anterior fazia um INSERT simples,
-- sem tratar conflito, o que causava o erro
--   "duplicate key value violates unique constraint
--    counting_setor_id_codigo_barras_key"
-- sempre que a mesma combinação (setor_id, codigo_barras) era
-- inserida duas vezes em sequência rápida — por exemplo quando a
-- câmera detecta o mesmo código em frames consecutivos antes do
-- primeiro INSERT terminar (corrigido também no client com um
-- cooldown de 1.5s entre leituras repetidas do mesmo código).
-- ---------------------------------------------------------------------

-- Caso precise recriar do zero (o Postgres não deixa trocar o tipo de
-- retorno de uma função existente com CREATE OR REPLACE):
-- DROP FUNCTION IF EXISTS increment_counting(text, uuid, uuid, text);

CREATE OR REPLACE FUNCTION increment_counting(
  p_id text,
  p_inv uuid,
  p_setor uuid,
  p_barcode text
)
RETURNS contagens
LANGUAGE plpgsql
AS $$
DECLARE
  v_sku text;
  v_descricao text;
  v_nao_cadastrado boolean;
  v_result contagens;
BEGIN
  -- Busca o produto na base importada (se existir)
  SELECT sku, descricao INTO v_sku, v_descricao
  FROM product_db
  WHERE codigo_barras = p_barcode
  LIMIT 1;

  v_nao_cadastrado := (v_sku IS NULL);

  INSERT INTO contagens (
    id, inventario_id, setor_id, codigo_barras, quantidade,
    sku, descricao, nao_cadastrado,
    data_primeira_leitura, data_ultima_leitura, created_at
  )
  VALUES (
    gen_random_uuid(), p_inv, p_setor, p_barcode, 1,
    v_sku, v_descricao, v_nao_cadastrado,
    now(), now(), now()
  )
  ON CONFLICT (setor_id, codigo_barras)
  DO UPDATE SET
    quantidade = contagens.quantidade + 1,
    data_ultima_leitura = now()
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;
