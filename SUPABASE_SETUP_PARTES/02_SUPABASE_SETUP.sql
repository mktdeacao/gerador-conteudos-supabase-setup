-- SOURCE: sql/011_post_media_bucket.sql
-- ============================================================

-- ============================================
-- BASE Content Studio v2 - Post Media Bucket
-- Fix: bucket 'post-media' was missing (code referenced it but only 'media' existed)
-- Applied manually via API on 2026-02-02
-- ============================================

-- Create post-media bucket (for scheduled posts uploads)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'post-media',
  'post-media',
  true,
  52428800, -- 50MB
  ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'video/mp4', 'video/webm', 'video/quicktime', 'application/pdf']
)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for post-media
CREATE POLICY "post-media public read" ON storage.objects 
FOR SELECT USING (bucket_id = 'post-media');

CREATE POLICY "post-media authenticated upload" ON storage.objects 
FOR INSERT WITH CHECK (bucket_id = 'post-media' AND auth.role() = 'authenticated');

CREATE POLICY "post-media authenticated update" ON storage.objects 
FOR UPDATE USING (bucket_id = 'post-media' AND auth.role() = 'authenticated');

CREATE POLICY "post-media authenticated delete" ON storage.objects 
FOR DELETE USING (bucket_id = 'post-media' AND auth.role() = 'authenticated');


-- ============================================================
-- SOURCE: sql/012_fix_trigger_v2.sql
-- ============================================================

-- ============================================
-- FIX: handle_new_user trigger - robust version
-- Fixes:
-- 1. Apostrophe in org name causing SQL error
-- 2. Slug with special characters
-- 3. ON CONFLICT for duplicate member
-- 4. EXCEPTION handler to not block user creation
-- ============================================

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger AS $$
DECLARE
  new_org_id uuid;
  user_name text;
  existing_invite record;
  safe_slug text;
BEGIN
  user_name := COALESCE(
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'display_name',
    split_part(NEW.email, '@', 1)
  );
  
  -- Check if there is a pending invite for this email
  SELECT * INTO existing_invite FROM invites 
  WHERE email = NEW.email 
    AND accepted_at IS NULL 
  ORDER BY created_at DESC 
  LIMIT 1;
  
  IF existing_invite IS NOT NULL THEN
    -- User was invited: add to EXISTING org
    INSERT INTO members (user_id, org_id, role, display_name, status)
    VALUES (NEW.id, existing_invite.org_id, existing_invite.role, user_name, 'active')
    ON CONFLICT (user_id, org_id) DO NOTHING;
    
    -- Mark invite as accepted
    UPDATE invites SET accepted_at = NOW() WHERE id = existing_invite.id;
  ELSE
    -- New standalone user: create default org
    -- Safe slug: only lowercase alphanumeric and hyphens
    safe_slug := lower(regexp_replace(user_name, '[^a-zA-Z0-9]', '-', 'g')) || '-' || substr(NEW.id::text, 1, 8);
    
    INSERT INTO organizations (name, slug)
    VALUES (
      user_name || ' Workspace', 
      safe_slug
    )
    RETURNING id INTO new_org_id;
    
    INSERT INTO members (user_id, org_id, role, display_name, status)
    VALUES (NEW.id, new_org_id, 'admin', user_name, 'active');
  END IF;
  
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Log error but don't block user creation
  RAISE WARNING 'handle_new_user error for %: %', NEW.email, SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- ============================================================
-- SOURCE: sql/013_add_comentario_cliente.sql
-- ============================================================

-- ============================================
-- Migration: Adicionar colunas de feedback do cliente
-- Data: 2026-02-19
-- Problema: Comentários de ajuste não estavam sendo salvos no conteúdo
-- ============================================

-- 1. Adicionar coluna para comentário do cliente
ALTER TABLE conteudos ADD COLUMN IF NOT EXISTS comentario_cliente TEXT;

-- 2. Adicionar coluna para nome do cliente que fez o feedback
ALTER TABLE conteudos ADD COLUMN IF NOT EXISTS cliente_nome_feedback VARCHAR(255);

-- 3. Migrar comentários existentes de aprovacoes_links para conteudos
UPDATE conteudos c
SET 
  comentario_cliente = a.comentario_cliente,
  cliente_nome_feedback = a.cliente_nome
FROM aprovacoes_links a
WHERE c.id = a.conteudo_id 
  AND a.status = 'ajuste'
  AND a.comentario_cliente IS NOT NULL
  AND c.comentario_cliente IS NULL;

-- 4. Criar índice para buscar conteúdos que precisam de ajuste
CREATE INDEX IF NOT EXISTS idx_conteudos_comentario ON conteudos(comentario_cliente) WHERE comentario_cliente IS NOT NULL;

-- ============================================
-- RESULTADO ESPERADO:
-- - 2 colunas novas em conteudos
-- - ~16 comentários migrados de aprovacoes_links
-- ============================================


-- ============================================================
-- SOURCE: sql/014_blog_integration.sql
-- ============================================================

-- =============================================
-- MIGRATION: Blog Integration
-- Data: 2026-02-22
-- Autor: Max (Clawdbot)
-- 
-- SEGURO: Apenas ADICIONA campos, não altera nada existente
-- ROLLBACK: Colunas nullable não afetam funcionamento
-- =============================================

-- 1. Campos WordPress na tabela clientes (NOVOS)
-- Permite cada cliente ter sua própria config de WordPress
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS wp_url TEXT;
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS wp_user TEXT;
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS wp_app_password TEXT;
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS wp_default_status TEXT DEFAULT 'draft';
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS wp_default_category_id INTEGER;

-- Comentários para documentação
COMMENT ON COLUMN clientes.wp_url IS 'URL do WordPress do cliente (ex: https://site.com.br)';
COMMENT ON COLUMN clientes.wp_user IS 'Usuário WordPress para autenticação REST API';
COMMENT ON COLUMN clientes.wp_app_password IS 'Application Password do WordPress (criptografar em produção)';
COMMENT ON COLUMN clientes.wp_default_status IS 'Status padrão ao publicar: draft ou publish';
COMMENT ON COLUMN clientes.wp_default_category_id IS 'ID da categoria padrão no WordPress';

-- 2. Campos de blog na tabela conteudos (NOVOS)
-- Rastreia posts publicados no WordPress
ALTER TABLE conteudos ADD COLUMN IF NOT EXISTS categoria TEXT DEFAULT 'social';
ALTER TABLE conteudos ADD COLUMN IF NOT EXISTS wp_post_id INTEGER;
ALTER TABLE conteudos ADD COLUMN IF NOT EXISTS wp_post_url TEXT;
ALTER TABLE conteudos ADD COLUMN IF NOT EXISTS wp_published_at TIMESTAMPTZ;

-- Comentários para documentação
COMMENT ON COLUMN conteudos.wp_post_id IS 'ID do post no WordPress após publicação';
COMMENT ON COLUMN conteudos.wp_post_url IS 'URL pública do post no WordPress';
COMMENT ON COLUMN conteudos.wp_published_at IS 'Data/hora de publicação no WordPress';

-- 3. Índice para filtrar conteúdos de blog (performance)
CREATE INDEX IF NOT EXISTS idx_conteudos_categoria_blog 
ON conteudos(empresa_id, categoria) 
WHERE categoria = 'blog';

-- 4. Verificação: listar colunas adicionadas
-- Execute separadamente para confirmar:
-- SELECT column_name, data_type, is_nullable 
-- FROM information_schema.columns 
-- WHERE table_name = 'clientes' AND column_name LIKE 'wp_%';


-- ============================================================
-- SOURCE: sql/015_campaigns_integration.sql
-- ============================================================

-- 015_campaigns_integration.sql
-- Dashboard de Campanhas Facebook Ads

-- 1. Campo ad_account_id no cliente
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS ad_account_id TEXT;
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS ad_account_name TEXT;

-- 2. Cache de campanhas (atualiza a cada request)
CREATE TABLE IF NOT EXISTS campaigns_cache (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  cliente_id UUID REFERENCES clientes(id) ON DELETE CASCADE,
  ad_account_id TEXT NOT NULL,
  campaign_id TEXT NOT NULL,
  campaign_name TEXT,
  status TEXT, -- ACTIVE, PAUSED, DELETED
  objective TEXT,
  daily_budget DECIMAL,
  lifetime_budget DECIMAL,
  spend DECIMAL DEFAULT 0,
  results INTEGER DEFAULT 0,
  cost_per_result DECIMAL,
  roas DECIMAL,
  raw_data JSONB,
  date_start DATE,
  date_stop DATE,
  fetched_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(cliente_id, campaign_id, date_start, date_stop)
);

-- 3. Índices para performance
CREATE INDEX IF NOT EXISTS idx_campaigns_cache_cliente ON campaigns_cache(cliente_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_cache_fetched ON campaigns_cache(fetched_at);

-- 4. RLS Policies
ALTER TABLE campaigns_cache ENABLE ROW LEVEL SECURITY;

-- Política: usuário só vê campanhas da sua org
DROP POLICY IF EXISTS "Users can view own org campaigns" ON campaigns_cache;
CREATE POLICY "Users can view own org campaigns" ON campaigns_cache
  FOR SELECT USING (
    org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active')
  );

-- Política: service role pode tudo
DROP POLICY IF EXISTS "Service role full access campaigns" ON campaigns_cache;
CREATE POLICY "Service role full access campaigns" ON campaigns_cache
  FOR ALL USING (true);


-- ============================================================
-- SOURCE: sql/016_acervo_digital.sql
-- ============================================================

-- ============================================
-- Migration 016: Acervo Digital (Google Drive Sync)
-- Permite criar categorias de acervo por cliente
-- linkadas a pastas do Google Drive
-- ============================================

-- 1. ACERVO_CATEGORIAS (categorias de acervo por cliente)
CREATE TABLE IF NOT EXISTS acervo_categorias (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id uuid REFERENCES organizations(id) ON DELETE CASCADE NOT NULL,
  cliente_id uuid REFERENCES clientes(id) ON DELETE CASCADE NOT NULL,
  
  -- Metadados da categoria
  titulo varchar(255) NOT NULL,
  descricao text,
  icone varchar(50) DEFAULT 'folder', -- lucide icon name
  ordem int DEFAULT 0,
  
  -- Link do Google Drive
  drive_folder_id varchar(255), -- ID da pasta no Drive
  drive_folder_url text, -- URL completa (pra facilitar)
  
  -- Configurações de sync
  sync_enabled boolean DEFAULT true,
  last_sync_at timestamptz,
  sync_status varchar(50) DEFAULT 'pending', -- pending, syncing, success, error
  sync_error text,
  
  -- Visibilidade
  is_public boolean DEFAULT true, -- cliente pode ver
  requires_password boolean DEFAULT false,
  password_hash varchar(255),
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  
  UNIQUE(cliente_id, titulo)
);

-- 2. ACERVO_ARQUIVOS (arquivos sincronizados do Drive)
CREATE TABLE IF NOT EXISTS acervo_arquivos (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  categoria_id uuid REFERENCES acervo_categorias(id) ON DELETE CASCADE NOT NULL,
  
  -- Dados do arquivo
  filename varchar(500) NOT NULL,
  mime_type varchar(100),
  file_size bigint,
  
  -- Google Drive info
  drive_file_id varchar(255) NOT NULL,
  drive_web_view_link text,
  drive_download_link text,
  drive_thumbnail_link text,
  
  -- Cache local (opcional - pra preview rápido)
  cached_thumbnail_url text,
  
  -- Metadados
  description text,
  tags text[] DEFAULT '{}',
  ordem int DEFAULT 0,
  
  -- Tracking
  drive_modified_at timestamptz, -- última modificação no Drive
  synced_at timestamptz DEFAULT now(),
  download_count int DEFAULT 0,
  
  created_at timestamptz DEFAULT now(),
  
  UNIQUE(categoria_id, drive_file_id)
);

-- 3. ACERVO_DOWNLOADS (log de downloads - analytics)
CREATE TABLE IF NOT EXISTS acervo_downloads (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  arquivo_id uuid REFERENCES acervo_arquivos(id) ON DELETE CASCADE NOT NULL,
  
  -- Quem baixou
  ip_address varchar(45),
  user_agent text,
  referer text,
  
  -- Quando
  downloaded_at timestamptz DEFAULT now()
);

-- ============================================
-- RLS (Row Level Security)
-- ============================================

ALTER TABLE acervo_categorias ENABLE ROW LEVEL SECURITY;
ALTER TABLE acervo_arquivos ENABLE ROW LEVEL SECURITY;
ALTER TABLE acervo_downloads ENABLE ROW LEVEL SECURITY;

-- Service role pode tudo
DO $policy$ BEGIN
  CREATE POLICY "service_role_all_categorias" ON acervo_categorias FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $policy$;

DO $policy$ BEGIN
  CREATE POLICY "service_role_all_arquivos" ON acervo_arquivos FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $policy$;

DO $policy$ BEGIN
  CREATE POLICY "service_role_all_downloads" ON acervo_downloads FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $policy$;

-- ============================================
-- INDEXES
-- ============================================

CREATE INDEX IF NOT EXISTS idx_acervo_categorias_cliente ON acervo_categorias(cliente_id);
CREATE INDEX IF NOT EXISTS idx_acervo_categorias_org ON acervo_categorias(org_id);
CREATE INDEX IF NOT EXISTS idx_acervo_arquivos_categoria ON acervo_arquivos(categoria_id);
CREATE INDEX IF NOT EXISTS idx_acervo_arquivos_drive_id ON acervo_arquivos(drive_file_id);
CREATE INDEX IF NOT EXISTS idx_acervo_downloads_arquivo ON acervo_downloads(arquivo_id);

-- ============================================
-- FUNCTIONS
-- ============================================

-- Função pra atualizar updated_at automaticamente
CREATE OR REPLACE FUNCTION update_acervo_categoria_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger
DROP TRIGGER IF EXISTS trigger_update_acervo_categoria ON acervo_categorias;
CREATE TRIGGER trigger_update_acervo_categoria
  BEFORE UPDATE ON acervo_categorias
  FOR EACH ROW
  EXECUTE FUNCTION update_acervo_categoria_timestamp();

-- ============================================
-- COMENTÁRIOS
-- ============================================

COMMENT ON TABLE acervo_categorias IS 'Categorias de acervo digital por cliente, linkadas a pastas do Google Drive';
COMMENT ON TABLE acervo_arquivos IS 'Arquivos sincronizados do Google Drive';
COMMENT ON TABLE acervo_downloads IS 'Log de downloads para analytics';

COMMENT ON COLUMN acervo_categorias.drive_folder_id IS 'ID da pasta no Google Drive (extraído da URL)';
COMMENT ON COLUMN acervo_categorias.sync_status IS 'Status: pending, syncing, success, error';
COMMENT ON COLUMN acervo_arquivos.drive_file_id IS 'ID único do arquivo no Google Drive';


-- ============================================================
-- SOURCE: sql/020_fix_aprovacoes_rls.sql
-- ============================================================

-- ============================================================
-- FIX: RLS para aprovacoes_links
-- Problema: políticas USING(true) permitiam qualquer usuário
-- autenticado ler/escrever aprovações de qualquer organização.
-- ============================================================

-- Remove políticas inseguras
DROP POLICY IF EXISTS "aprovacoes_public_read"  ON aprovacoes_links;
DROP POLICY IF EXISTS "aprovacoes_org_write"    ON aprovacoes_links;
DROP POLICY IF EXISTS "aprovacoes_update"       ON aprovacoes_links;

-- SELECT:
--   • Usuário anônimo pode ler (página de aprovação pública usa token único)
--   • Usuário autenticado só vê aprovações da própria org
CREATE POLICY "aprovacoes_select" ON aprovacoes_links
  FOR SELECT USING (
    auth.uid() IS NULL                          -- acesso público (link de aprovação)
    OR org_id IN (SELECT get_user_org_ids())    -- membro da org
  );

-- INSERT: apenas membros autenticados da org
CREATE POLICY "aprovacoes_insert" ON aprovacoes_links
  FOR INSERT WITH CHECK (
    org_id IN (SELECT get_user_org_ids())
  );

-- UPDATE:
--   • Anônimo pode atualizar (cliente aprova/rejeita via link público)
--   • Membro autenticado da org também pode atualizar
CREATE POLICY "aprovacoes_update" ON aprovacoes_links
  FOR UPDATE USING (
    auth.uid() IS NULL
    OR org_id IN (SELECT get_user_org_ids())
  );

-- DELETE: apenas admins/gestores da org
CREATE POLICY "aprovacoes_delete" ON aprovacoes_links
  FOR DELETE USING (
    is_org_manager(org_id)
  );


-- ============================================================
-- SOURCE: sql/021_performance_indexes.sql
-- ============================================================

-- ============================================================
-- PERFORMANCE: Índices críticos para queries de alta frequência
-- Execute no Supabase SQL Editor
-- ============================================================

-- scheduled_posts: cron + calendário fazem full table scan sem isso
CREATE INDEX IF NOT EXISTS ix_scheduled_posts_org_scheduled
  ON scheduled_posts(org_id, scheduled_at);

CREATE INDEX IF NOT EXISTS ix_scheduled_posts_status_scheduled
  ON scheduled_posts(status, scheduled_at)
  WHERE status = 'scheduled';

CREATE INDEX IF NOT EXISTS ix_scheduled_posts_cliente
  ON scheduled_posts(cliente_id);

-- conteudos: queries por mês/ano e empresa são muito comuns
CREATE INDEX IF NOT EXISTS ix_conteudos_org_mes_ano
  ON conteudos(org_id, mes, ano);

CREATE INDEX IF NOT EXISTS ix_conteudos_empresa_status
  ON conteudos(empresa_id, status);

CREATE INDEX IF NOT EXISTS ix_conteudos_data_publicacao
  ON conteudos(data_publicacao)
  WHERE data_publicacao IS NOT NULL;

-- notifications: realtime subscription filtra por user_id
CREATE INDEX IF NOT EXISTS ix_notifications_user_read
  ON notifications(user_id, read, created_at DESC);

-- aprovacoes_links: lookup por token (página pública)
CREATE INDEX IF NOT EXISTS ix_aprovacoes_links_token
  ON aprovacoes_links(token);

CREATE INDEX IF NOT EXISTS ix_aprovacoes_links_conteudo
  ON aprovacoes_links(conteudo_id);

-- activity_log: consultas por org + created_at descendente
CREATE INDEX IF NOT EXISTS ix_activity_log_org_created
  ON activity_log(org_id, created_at DESC);

-- members: lookup frequente por user_id
CREATE INDEX IF NOT EXISTS ix_members_user_status
  ON members(user_id, status);

-- messages: chat por cliente
CREATE INDEX IF NOT EXISTS ix_messages_cliente_created
  ON messages(cliente_id, created_at DESC);

-- Add check constraint: scheduled_at não pode ser no passado ao criar
-- (soft validation — não bloqueia updates de status como 'published')
-- ALTER TABLE scheduled_posts
--   ADD CONSTRAINT chk_scheduled_at_future
--   CHECK (status != 'scheduled' OR scheduled_at > now() - interval '1 minute');


-- ============================================================
-- SOURCE: sql/022_fix_status_check.sql
-- ============================================================

-- ============================================================
-- FIX: conteudos_status_check desatualizado
-- A constraint original (001) só aceitava o fluxo antigo
-- (rascunho, conteudo, design, aprovacao_cliente, ajustes,
-- aprovado_agendado, concluido). O app usa o fluxo novo de 11
-- status (STATUS_CONFIG em src/lib/utils.ts) e algumas telas
-- ainda GRAVAM status legados (ex.: nova-demanda grava
-- 'producao', normalizado só na leitura via LEGACY_STATUS_MAP).
-- Solução: constraint com a união dos dois vocabulários.
-- ============================================================

ALTER TABLE conteudos DROP CONSTRAINT IF EXISTS conteudos_status_check;
ALTER TABLE conteudos ADD CONSTRAINT conteudos_status_check CHECK (status IN (
  -- fluxo atual (STATUS_CONFIG)
  'rascunho','aguardando_design','conteudo','aprovacao_interna','aprovacao_cliente',
  'ajuste','aguardando_agendamento','agendado','publicado','cancelado','arquivado',
  -- legados ainda gravados por algumas telas (LEGACY_STATUS_MAP)
  'nova_solicitacao','producao','revisao','design','aprovacao','ajustes',
  'aprovado','aprovado_agendado','concluido','ajuste_solicitado'
));


-- ============================================================
-- SOURCE: sql/023_org_integrations.sql
-- ============================================================

-- ============================================================
-- FIX: colunas de integração por organização ausentes no schema
-- A feature "Upload-Post e Telegram por agência" (Configurações →
-- Integrações) grava nessas colunas, mas a migração nunca foi
-- salva no repo. Erro na tela: "Could not find the
-- 'telegram_bot_token' column of 'organizations'".
-- ============================================================

ALTER TABLE organizations ADD COLUMN IF NOT EXISTS upload_post_api_key text;
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS telegram_bot_token text;
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS telegram_chat_id text;
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS telegram_webhook_secret text;

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- SOURCE: sql/024_missing_columns.sql
-- ============================================================

-- ============================================================
-- FIX: colunas usadas pelo app mas ausentes do schema versionado
-- - conteudos.hora_publicacao: gravada pelo card do conteúdo e
--   pelo fluxo de agendamento (commit "usa hora_publicacao").
-- - members.custom_permissions / email_notifications: usadas pela
--   tela Equipe (permissões granulares). NULL = defaults do role.
-- Erro na tela: "Could not find the 'hora_publicacao' column".
-- ============================================================

ALTER TABLE conteudos ADD COLUMN IF NOT EXISTS hora_publicacao text;
ALTER TABLE members   ADD COLUMN IF NOT EXISTS custom_permissions jsonb;
ALTER TABLE members   ADD COLUMN IF NOT EXISTS email_notifications jsonb;

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- SOURCE: sql/add_categoria_entrega.sql
-- ============================================================

-- Migration: Adicionar categoria de entrega
-- Data: 2026-02-07
-- Descrição: Permite criar demandas que não são posts de redes sociais

-- 1. Adicionar coluna categoria na tabela conteudos
ALTER TABLE conteudos 
ADD COLUMN IF NOT EXISTS categoria VARCHAR(50) DEFAULT 'post_social';

-- 2. Adicionar colunas categoria e tipo na tabela solicitacoes
ALTER TABLE solicitacoes 
ADD COLUMN IF NOT EXISTS categoria VARCHAR(50) DEFAULT 'post_social';

ALTER TABLE solicitacoes 
ADD COLUMN IF NOT EXISTS tipo VARCHAR(50);

-- 3. Criar índice para melhor performance em filtros
CREATE INDEX IF NOT EXISTS idx_conteudos_categoria ON conteudos(categoria);
CREATE INDEX IF NOT EXISTS idx_solicitacoes_categoria ON solicitacoes(categoria);

-- 4. Comentários para documentação
COMMENT ON COLUMN conteudos.categoria IS 'Categoria de entrega: post_social, material_grafico, apresentacao, video_offline';
COMMENT ON COLUMN solicitacoes.categoria IS 'Categoria de entrega: post_social, material_grafico, apresentacao, video_offline';
COMMENT ON COLUMN solicitacoes.tipo IS 'Tipo específico dentro da categoria (ex: banner, flyer, pitch)';


-- ============================================================
-- SOURCE: scripts/migration.sql
-- ============================================================


ALTER TABLE organizations ADD COLUMN IF NOT EXISTS brand_color text DEFAULT '#6366F1';
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS accent_color text DEFAULT '#3B82F6';
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS favicon_url text;
ALTER TABLE members ADD COLUMN IF NOT EXISTS notification_prefs jsonb DEFAULT '{}'::jsonb;


-- ============================================================
-- SOURCE: supabase/migrations/003_billing.sql
-- ============================================================

-- =============================================
-- BILLING TABLES AND COLUMNS
-- Run this in Supabase SQL Editor
-- =============================================

-- Add billing columns to organizations
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT UNIQUE;
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS stripe_subscription_id TEXT UNIQUE;
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS plan_id TEXT DEFAULT 'starter';
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS subscription_status TEXT DEFAULT 'trialing';
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS current_period_start TIMESTAMPTZ;
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS current_period_end TIMESTAMPTZ;
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS cancel_at_period_end BOOLEAN DEFAULT FALSE;
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS trial_end TIMESTAMPTZ;

-- Create invoices table
CREATE TABLE IF NOT EXISTS invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  stripe_invoice_id TEXT UNIQUE NOT NULL,
  amount INTEGER NOT NULL,
  currency TEXT DEFAULT 'brl',
  status TEXT DEFAULT 'draft',
  invoice_url TEXT,
  invoice_pdf TEXT,
  period_start TIMESTAMPTZ,
  period_end TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create usage_records table (for tracking monthly usage)
CREATE TABLE IF NOT EXISTS usage_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  month TEXT NOT NULL, -- YYYY-MM format
  clients_count INTEGER DEFAULT 0,
  users_count INTEGER DEFAULT 0,
  contents_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(organization_id, month)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_organizations_stripe_customer ON organizations(stripe_customer_id);
CREATE INDEX IF NOT EXISTS idx_organizations_plan ON organizations(plan_id);
CREATE INDEX IF NOT EXISTS idx_invoices_org ON invoices(organization_id);
CREATE INDEX IF NOT EXISTS idx_usage_org_month ON usage_records(organization_id, month);

-- RLS Policies for invoices
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their organization invoices" ON invoices;
CREATE POLICY "Users can view their organization invoices" ON invoices
  FOR SELECT USING (
    organization_id IN (
      SELECT org_id FROM members
      WHERE user_id = auth.uid() AND status = 'active'
    )
  );

-- RLS Policies for usage_records
ALTER TABLE usage_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their organization usage" ON usage_records;
CREATE POLICY "Users can view their organization usage" ON usage_records
  FOR SELECT USING (
    organization_id IN (
      SELECT org_id FROM members
      WHERE user_id = auth.uid() AND status = 'active'
    )
  );

-- Grant permissions
GRANT SELECT ON invoices TO authenticated;
GRANT SELECT ON usage_records TO authenticated;


-- ============================================================
-- SOURCE: supabase/migrations/20260205_approvals.sql
-- ============================================================

-- ============================================
-- MÓDULO 2: Sistema de Aprovações
-- Data: 05/02/2026
-- ============================================

-- Tabela de histórico de aprovações (internas e externas)
CREATE TABLE IF NOT EXISTS approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  conteudo_id uuid NOT NULL REFERENCES conteudos(id) ON DELETE CASCADE,
  type varchar(20) NOT NULL CHECK (type IN ('internal', 'external')),
  status varchar(20) NOT NULL CHECK (status IN ('pending', 'approved', 'rejected', 'adjustment')),
  reviewer_id uuid REFERENCES auth.users(id),
  reviewer_name varchar(255),
  comment text,
  created_at timestamptz DEFAULT now(),
  reviewed_at timestamptz,
  
  -- Metadata
  previous_status varchar(50),
  new_status varchar(50),
  link_token varchar(255) -- Para vincular com aprovacoes_links
);

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_approvals_conteudo ON approvals(conteudo_id);
CREATE INDEX IF NOT EXISTS idx_approvals_org ON approvals(org_id);
CREATE INDEX IF NOT EXISTS idx_approvals_type ON approvals(type);
CREATE INDEX IF NOT EXISTS idx_approvals_status ON approvals(status);
CREATE INDEX IF NOT EXISTS idx_approvals_created ON approvals(created_at DESC);

-- Adicionar campo sub_status na tabela conteudos (para controle granular)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'conteudos' AND column_name = 'sub_status'
  ) THEN
    ALTER TABLE conteudos ADD COLUMN sub_status varchar(50);
  END IF;
END $$;

-- Adicionar campo internal_approved (aprovação interna já feita)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'conteudos' AND column_name = 'internal_approved'
  ) THEN
    ALTER TABLE conteudos ADD COLUMN internal_approved boolean DEFAULT false;
  END IF;
END $$;

-- Adicionar campo internal_approved_by
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'conteudos' AND column_name = 'internal_approved_by'
  ) THEN
    ALTER TABLE conteudos ADD COLUMN internal_approved_by uuid REFERENCES auth.users(id);
  END IF;
END $$;

-- Adicionar campo internal_approved_at
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'conteudos' AND column_name = 'internal_approved_at'
  ) THEN
    ALTER TABLE conteudos ADD COLUMN internal_approved_at timestamptz;
  END IF;
END $$;

-- RLS Policies
ALTER TABLE approvals ENABLE ROW LEVEL SECURITY;

-- Policy: membros podem ver aprovações da sua org
CREATE POLICY "Members can view org approvals" ON approvals
  FOR SELECT USING (
    org_id IN (
      SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
    )
  );

-- Policy: membros podem inserir aprovações na sua org
CREATE POLICY "Members can create org approvals" ON approvals
  FOR INSERT WITH CHECK (
    org_id IN (
      SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
    )
  );

-- Policy: membros podem atualizar aprovações da sua org
CREATE POLICY "Members can update org approvals" ON approvals
  FOR UPDATE USING (
    org_id IN (
      SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
    )
  );

-- Comentário na tabela
COMMENT ON TABLE approvals IS 'Histórico completo de aprovações internas e externas';
COMMENT ON COLUMN approvals.type IS 'internal = aprovação da equipe, external = aprovação do cliente';
COMMENT ON COLUMN approvals.status IS 'pending = aguardando, approved = aprovado, rejected = rejeitado, adjustment = pediu ajuste';


-- ============================================================
-- SOURCE: supabase/migrations/20260205_m1_workflow_v3.sql
-- ============================================================

-- M1: Workflow Kanban V3 - Novos status e sub-status
-- Data: 2026-02-05

-- Adicionar sub_status na tabela conteudos
ALTER TABLE conteudos 
ADD COLUMN IF NOT EXISTS sub_status varchar(50) DEFAULT NULL;

-- Adicionar campo de mídia se não existir
ALTER TABLE conteudos 
ADD COLUMN IF NOT EXISTS midia_url text DEFAULT NULL,
ADD COLUMN IF NOT EXISTS midia_type varchar(50) DEFAULT NULL,
ADD COLUMN IF NOT EXISTS canais text[] DEFAULT '{}';

-- Atualizar status existentes para o novo padrão
UPDATE conteudos SET status = 'conteudo' WHERE status = 'producao';
UPDATE conteudos SET status = 'aprovacao_cliente' WHERE status = 'aprovacao';
UPDATE conteudos SET status = 'aguardando_agendamento' WHERE status = 'aprovado';

-- Índice para performance
CREATE INDEX IF NOT EXISTS idx_conteudos_sub_status ON conteudos(sub_status) WHERE sub_status IS NOT NULL;

-- Comentários
COMMENT ON COLUMN conteudos.sub_status IS 'Sub-status para a coluna Conteúdo: aguardando_texto, texto_concluido, aguardando_design, design_concluido';
COMMENT ON COLUMN conteudos.midia_url IS 'URL da mídia principal (imagem ou vídeo)';
COMMENT ON COLUMN conteudos.midia_type IS 'Tipo da mídia: image/*, video/*';
COMMENT ON COLUMN conteudos.canais IS 'Array de canais para publicação: instagram, tiktok, facebook, etc';


-- ============================================================
-- SOURCE: supabase/migrations/20260205_m4_calendar_dates.sql
-- ============================================================

-- M4: Calendário de Datas Importantes por Cliente
-- Data: 2026-02-05

-- Tabela de datas importantes por cliente
CREATE TABLE IF NOT EXISTS client_calendar_dates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id uuid NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
  org_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  date date NOT NULL,
  title varchar(255) NOT NULL,
  description text,
  priority varchar(20) DEFAULT 'medium' CHECK (priority IN ('critical', 'high', 'medium', 'low')),
  category varchar(50) DEFAULT 'geral',
  recurring boolean DEFAULT false,
  recurring_type varchar(20), -- 'yearly', 'monthly'
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_calendar_dates_cliente ON client_calendar_dates(cliente_id);
CREATE INDEX IF NOT EXISTS idx_calendar_dates_date ON client_calendar_dates(date);
CREATE INDEX IF NOT EXISTS idx_calendar_dates_org ON client_calendar_dates(org_id);

-- RLS
ALTER TABLE client_calendar_dates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view calendar dates of their org"
  ON client_calendar_dates FOR SELECT
  USING (org_id IN (
    SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
  ));

CREATE POLICY "Users can insert calendar dates in their org"
  ON client_calendar_dates FOR INSERT
  WITH CHECK (org_id IN (
    SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
  ));

CREATE POLICY "Users can update calendar dates in their org"
  ON client_calendar_dates FOR UPDATE
  USING (org_id IN (
    SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
  ));

CREATE POLICY "Users can delete calendar dates in their org"
  ON client_calendar_dates FOR DELETE
  USING (org_id IN (
    SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
  ));

-- Comentários
COMMENT ON TABLE client_calendar_dates IS 'Datas importantes do calendário por cliente (feriados, datas comerciais, etc)';
COMMENT ON COLUMN client_calendar_dates.priority IS 'Prioridade: critical (vermelho), high (laranja), medium (azul), low (cinza)';
COMMENT ON COLUMN client_calendar_dates.category IS 'Categoria: feriado, comercial, institucional, campanha, etc';


-- ============================================================
-- SOURCE: supabase/migrations/20260206_add_feedback_fields.sql
-- ============================================================

-- Adicionar campos para feedback do cliente diretamente no conteúdo
ALTER TABLE conteudos 
ADD COLUMN IF NOT EXISTS comentario_cliente TEXT,
ADD COLUMN IF NOT EXISTS cliente_nome_feedback TEXT;

-- Migrar feedbacks existentes da tabela approvals para conteudos
UPDATE conteudos c
SET 
  comentario_cliente = a.comment,
  cliente_nome_feedback = a.reviewer_name
FROM approvals a
WHERE a.conteudo_id = c.id 
  AND a.type = 'external' 
  AND a.status = 'adjustment'
  AND c.comentario_cliente IS NULL
  AND a.comment IS NOT NULL;

-- Índice para busca por conteúdos com feedback pendente
CREATE INDEX IF NOT EXISTS idx_conteudos_feedback ON conteudos(status) WHERE comentario_cliente IS NOT NULL;


-- ============================================================
