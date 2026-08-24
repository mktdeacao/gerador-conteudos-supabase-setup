-- Hotfix: coluna usada pela integração de blog
-- Execute este arquivo antes de repetir a parte 02.
ALTER TABLE conteudos ADD COLUMN IF NOT EXISTS categoria varchar(50) DEFAULT 'social';
CREATE INDEX IF NOT EXISTS idx_conteudos_categoria_blog
  ON conteudos(empresa_id, categoria)
  WHERE categoria = 'blog';
