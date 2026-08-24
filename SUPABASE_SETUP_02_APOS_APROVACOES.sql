-- Continuação após o hotfix de aprovacoes_links.

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
