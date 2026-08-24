-- SOURCE: supabase/migrations/20260225_create_acervos_v2.sql
-- ============================================================

-- Migration: Criar sistema de Acervo Digital (CORRIGIDO)
-- Data: 2026-02-25
-- Autor: Max (Agência BASE)

-- ============================================
-- FASE 1.1: Criar tabela acervos
-- ============================================
CREATE TABLE IF NOT EXISTS acervos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  org_id UUID REFERENCES organizations(id),
  cliente_id UUID REFERENCES clientes(id) ON DELETE CASCADE,
  
  -- Identificação
  titulo VARCHAR(255) NOT NULL,
  slug VARCHAR(100) NOT NULL,
  descricao TEXT,
  icone VARCHAR(10) DEFAULT '📁',
  
  -- Origem dos arquivos
  tipo_origem VARCHAR(20) DEFAULT 'drive',
  drive_folder_id VARCHAR(255),
  drive_folder_url TEXT,
  
  -- Config
  visibilidade VARCHAR(20) DEFAULT 'publico',
  ordem INT DEFAULT 0,
  ativo BOOLEAN DEFAULT true,
  
  -- Metadata
  total_arquivos INT DEFAULT 0,
  ultimo_sync TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(cliente_id, slug)
);

-- ============================================
-- FASE 1.2: Criar tabela acervo_arquivos
-- ============================================
CREATE TABLE IF NOT EXISTS acervo_arquivos (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  acervo_id UUID REFERENCES acervos(id) ON DELETE CASCADE,
  
  -- Arquivo
  nome VARCHAR(255) NOT NULL,
  tipo VARCHAR(100),
  tamanho BIGINT,
  
  -- URLs
  url_original TEXT,
  url_thumbnail TEXT,
  url_download TEXT,
  
  -- Metadata
  drive_file_id VARCHAR(255),
  ordem INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- FASE 1.3: Criar índices
-- ============================================
CREATE INDEX IF NOT EXISTS idx_acervos_cliente_id ON acervos(cliente_id);
CREATE INDEX IF NOT EXISTS idx_acervos_org_id ON acervos(org_id);
CREATE INDEX IF NOT EXISTS idx_acervos_slug ON acervos(slug);
CREATE INDEX IF NOT EXISTS idx_acervos_ativo ON acervos(ativo);
CREATE INDEX IF NOT EXISTS idx_acervo_arquivos_acervo_id ON acervo_arquivos(acervo_id);

-- ============================================
-- RLS Policies (CORRIGIDO - usa 'members' ao invés de 'organization_members')
-- ============================================

-- Habilitar RLS
ALTER TABLE acervos ENABLE ROW LEVEL SECURITY;
ALTER TABLE acervo_arquivos ENABLE ROW LEVEL SECURITY;

-- Políticas para acervos
CREATE POLICY "Acervos públicos visíveis para todos" ON acervos
  FOR SELECT
  USING (visibilidade = 'publico' AND ativo = true);

CREATE POLICY "Membros da org podem ver todos acervos" ON acervos
  FOR SELECT
  USING (
    org_id IN (
      SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
    )
  );

CREATE POLICY "Membros da org podem criar acervos" ON acervos
  FOR INSERT
  WITH CHECK (
    org_id IN (
      SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
    )
  );

CREATE POLICY "Membros da org podem atualizar acervos" ON acervos
  FOR UPDATE
  USING (
    org_id IN (
      SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
    )
  );

CREATE POLICY "Membros da org podem deletar acervos" ON acervos
  FOR DELETE
  USING (
    org_id IN (
      SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
    )
  );

-- Políticas para acervo_arquivos
CREATE POLICY "Arquivos de acervos públicos visíveis" ON acervo_arquivos
  FOR SELECT
  USING (
    acervo_id IN (
      SELECT id FROM acervos WHERE visibilidade = 'publico' AND ativo = true
    )
  );

CREATE POLICY "Membros podem ver todos arquivos" ON acervo_arquivos
  FOR SELECT
  USING (
    acervo_id IN (
      SELECT a.id FROM acervos a
      JOIN members m ON a.org_id = m.org_id
      WHERE m.user_id = auth.uid() AND m.status = 'active'
    )
  );

CREATE POLICY "Membros podem gerenciar arquivos" ON acervo_arquivos
  FOR ALL
  USING (
    acervo_id IN (
      SELECT a.id FROM acervos a
      JOIN members m ON a.org_id = m.org_id
      WHERE m.user_id = auth.uid() AND m.status = 'active'
    )
  );

-- ============================================
-- Função para atualizar updated_at
-- ============================================
CREATE OR REPLACE FUNCTION update_acervos_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS acervos_updated_at ON acervos;
CREATE TRIGGER acervos_updated_at
  BEFORE UPDATE ON acervos
  FOR EACH ROW
  EXECUTE FUNCTION update_acervos_updated_at();

-- ============================================
-- Função para atualizar total_arquivos
-- ============================================
CREATE OR REPLACE FUNCTION update_acervo_total_arquivos()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE acervos SET total_arquivos = total_arquivos + 1 WHERE id = NEW.acervo_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE acervos SET total_arquivos = total_arquivos - 1 WHERE id = OLD.acervo_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS acervo_arquivos_count ON acervo_arquivos;
CREATE TRIGGER acervo_arquivos_count
  AFTER INSERT OR DELETE ON acervo_arquivos
  FOR EACH ROW
  EXECUTE FUNCTION update_acervo_total_arquivos();


-- ============================================================
-- SOURCE: supabase/migrations/20260227_aprovadores.sql
-- ============================================================

-- Migration: Sistema de Aprovadores
-- Data: 2026-02-27
-- Baseado no modelo "Aprova Aí"

-- Tabela de aprovadores (internos e clientes)
CREATE TABLE IF NOT EXISTS aprovadores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  empresa_id UUID NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
  
  -- Dados do aprovador
  nome VARCHAR(255) NOT NULL,
  email VARCHAR(255),
  whatsapp VARCHAR(20) NOT NULL, -- formato: 5531999999999
  pais VARCHAR(5) DEFAULT '+55',
  
  -- Tipo e nível
  tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('interno', 'cliente', 'designer')),
  nivel INTEGER NOT NULL DEFAULT 1, -- ordem de aprovação (1 = primeiro, 2 = segundo...)
  
  -- Permissões
  pode_editar_legenda BOOLEAN DEFAULT false,
  recebe_notificacao BOOLEAN DEFAULT true,
  
  -- Status
  ativo BOOLEAN DEFAULT true,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_aprovadores_empresa ON aprovadores(empresa_id);
CREATE INDEX IF NOT EXISTS idx_aprovadores_tipo ON aprovadores(tipo);
CREATE INDEX IF NOT EXISTS idx_aprovadores_nivel ON aprovadores(nivel);

-- Trigger para updated_at
CREATE OR REPLACE FUNCTION update_aprovadores_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_aprovadores_updated_at ON aprovadores;
CREATE TRIGGER trigger_aprovadores_updated_at
  BEFORE UPDATE ON aprovadores
  FOR EACH ROW
  EXECUTE FUNCTION update_aprovadores_updated_at();

-- Tabela de histórico de aprovações
CREATE TABLE IF NOT EXISTS aprovacoes_historico (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conteudo_id UUID NOT NULL REFERENCES conteudos(id) ON DELETE CASCADE,
  aprovador_id UUID REFERENCES aprovadores(id) ON DELETE SET NULL,
  
  -- Dados da aprovação
  status VARCHAR(20) NOT NULL CHECK (status IN ('aprovado', 'reprovado', 'pendente')),
  nivel INTEGER NOT NULL,
  comentario TEXT,
  
  -- Dados extras
  whatsapp_usado VARCHAR(20),
  respondido_em TIMESTAMPTZ,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_aprovacoes_conteudo ON aprovacoes_historico(conteudo_id);
CREATE INDEX IF NOT EXISTS idx_aprovacoes_status ON aprovacoes_historico(status);

-- RLS (Row Level Security)
ALTER TABLE aprovadores ENABLE ROW LEVEL SECURITY;
ALTER TABLE aprovacoes_historico ENABLE ROW LEVEL SECURITY;

-- Políticas básicas (ajustar conforme necessidade)
CREATE POLICY "Aprovadores visíveis para todos autenticados" ON aprovadores
  FOR SELECT USING (true);

CREATE POLICY "Aprovadores editáveis por admins" ON aprovadores
  FOR ALL USING (true);

CREATE POLICY "Histórico visível para todos" ON aprovacoes_historico
  FOR SELECT USING (true);

CREATE POLICY "Histórico inserível" ON aprovacoes_historico
  FOR INSERT WITH CHECK (true);

-- Comentários
COMMENT ON TABLE aprovadores IS 'Aprovadores de conteúdo (internos e clientes)';
COMMENT ON TABLE aprovacoes_historico IS 'Histórico de aprovações por conteúdo';
COMMENT ON COLUMN aprovadores.tipo IS 'interno = equipe interna, cliente = aprovador do cliente, designer = quem cria';
COMMENT ON COLUMN aprovadores.nivel IS 'Ordem de aprovação: 1 = primeiro a aprovar, 2 = segundo, etc';


-- ============================================================
-- SOURCE: supabase/migrations/20260310_aprovadores_canais.sql
-- ============================================================

-- Migration: Canais de Notificação para Aprovadores
-- Data: 2026-03-10
-- Adiciona suporte a múltiplos canais (WhatsApp, Email, Telegram)

-- Adicionar coluna telegram_id
ALTER TABLE aprovadores 
ADD COLUMN IF NOT EXISTS telegram_id VARCHAR(100);

-- Adicionar coluna canais_notificacao (array de strings)
-- Valores possíveis: 'whatsapp', 'email', 'telegram'
ALTER TABLE aprovadores 
ADD COLUMN IF NOT EXISTS canais_notificacao TEXT[] DEFAULT ARRAY['whatsapp']::TEXT[];

-- Comentários
COMMENT ON COLUMN aprovadores.telegram_id IS 'ID ou username do Telegram (ex: @usuario ou 957707348)';
COMMENT ON COLUMN aprovadores.canais_notificacao IS 'Canais de notificação ativos: whatsapp, email, telegram';

-- Índice para busca por canal
CREATE INDEX IF NOT EXISTS idx_aprovadores_canais ON aprovadores USING GIN (canais_notificacao);

-- Migrar dados existentes: se recebe_notificacao = true e tem whatsapp, definir ['whatsapp']
UPDATE aprovadores 
SET canais_notificacao = ARRAY['whatsapp']::TEXT[]
WHERE recebe_notificacao = true 
  AND whatsapp IS NOT NULL 
  AND whatsapp != ''
  AND canais_notificacao IS NULL;

-- Se tem email preenchido, adicionar email aos canais
UPDATE aprovadores 
SET canais_notificacao = array_append(canais_notificacao, 'email')
WHERE email IS NOT NULL 
  AND email != ''
  AND NOT ('email' = ANY(canais_notificacao));


-- ============================================================
-- SOURCE: supabase/migrations/20260311_capa_url.sql
-- ============================================================

-- Migration: add capa_url to conteudos table
ALTER TABLE conteudos ADD COLUMN IF NOT EXISTS capa_url TEXT DEFAULT NULL;
COMMENT ON COLUMN conteudos.capa_url IS 'URL da imagem de capa/thumbnail selecionada (upload ou frame extraído do vídeo)';


-- ============================================================
-- SOURCE: supabase/migrations/20260314_scheduled_posts_cover_url.sql
-- ============================================================

-- Migration: add cover_url to scheduled_posts table
ALTER TABLE scheduled_posts ADD COLUMN IF NOT EXISTS cover_url TEXT DEFAULT NULL;
COMMENT ON COLUMN scheduled_posts.cover_url IS 'URL da imagem de capa/thumbnail do vídeo selecionada pelo usuário';
