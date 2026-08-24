-- BASE Content Studio / Gerador de Conteúdos
-- ARQUIVO FINAL ÚNICO para continuar uma instalação parcialmente executada.
-- Execute este arquivo inteiro no Supabase SQL Editor.
-- Pode ser executado novamente: hotfixes, policies e triggers são seguros.
-- Não contém credenciais.

-- ============================================================
-- HOTFIX BLOG
-- ============================================================
-- Hotfix: coluna usada pela integração de blog
-- Execute este arquivo antes de repetir a parte 02.
ALTER TABLE conteudos ADD COLUMN IF NOT EXISTS categoria varchar(50) DEFAULT 'social';
CREATE INDEX IF NOT EXISTS idx_conteudos_categoria_blog
  ON conteudos(empresa_id, categoria)
  WHERE categoria = 'blog';


-- ============================================================
-- HOTFIX APROVAÇÕES
-- ============================================================
-- Hotfix: RLS de aprovacoes_links
-- Corrige o uso incorreto de org_id.
-- Execute este arquivo no Supabase SQL Editor.

DROP POLICY IF EXISTS "aprovacoes_select" ON aprovacoes_links;
DROP POLICY IF EXISTS "aprovacoes_insert" ON aprovacoes_links;
DROP POLICY IF EXISTS "aprovacoes_update" ON aprovacoes_links;
DROP POLICY IF EXISTS "aprovacoes_delete" ON aprovacoes_links;

CREATE POLICY "aprovacoes_select" ON aprovacoes_links
  FOR SELECT USING (
    auth.uid() IS NULL
    OR empresa_id IN (
      SELECT id FROM clientes WHERE org_id IN (SELECT get_user_org_ids())
    )
  );

CREATE POLICY "aprovacoes_insert" ON aprovacoes_links
  FOR INSERT WITH CHECK (
    empresa_id IN (
      SELECT id FROM clientes WHERE org_id IN (SELECT get_user_org_ids())
    )
  );

CREATE POLICY "aprovacoes_update" ON aprovacoes_links
  FOR UPDATE USING (
    auth.uid() IS NULL
    OR empresa_id IN (
      SELECT id FROM clientes WHERE org_id IN (SELECT get_user_org_ids())
    )
  );

CREATE POLICY "aprovacoes_delete" ON aprovacoes_links
  FOR DELETE USING (
    empresa_id IN (
      SELECT id FROM clientes WHERE org_id IN (SELECT get_user_org_ids())
    )
  );


-- ============================================================
-- MIGRATIONS RESTANTES (a partir da 021)
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
DROP POLICY IF EXISTS "Members can view org approvals" ON approvals;
CREATE POLICY "Members can view org approvals" ON approvals
  FOR SELECT USING (
    org_id IN (
      SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
    )
  );

-- Policy: membros podem inserir aprovações na sua org
DROP POLICY IF EXISTS "Members can create org approvals" ON approvals;
CREATE POLICY "Members can create org approvals" ON approvals
  FOR INSERT WITH CHECK (
    org_id IN (
      SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
    )
  );

-- Policy: membros podem atualizar aprovações da sua org
DROP POLICY IF EXISTS "Members can update org approvals" ON approvals;
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

DROP POLICY IF EXISTS "Users can view calendar dates of their org" ON client_calendar_dates;

CREATE POLICY "Users can view calendar dates of their org"
  ON client_calendar_dates FOR SELECT
  USING (org_id IN (
    SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
  ));

DROP POLICY IF EXISTS "Users can insert calendar dates in their org" ON client_calendar_dates;

CREATE POLICY "Users can insert calendar dates in their org"
  ON client_calendar_dates FOR INSERT
  WITH CHECK (org_id IN (
    SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
  ));

DROP POLICY IF EXISTS "Users can update calendar dates in their org" ON client_calendar_dates;

CREATE POLICY "Users can update calendar dates in their org"
  ON client_calendar_dates FOR UPDATE
  USING (org_id IN (
    SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
  ));

DROP POLICY IF EXISTS "Users can delete calendar dates in their org" ON client_calendar_dates;

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
-- SOURCE: supabase/migrations/20260206_create_tasks_table.sql
-- ============================================================

-- ============================================
-- MAX TASKS - Sistema de Tarefas
-- ============================================

-- Tabela principal de tarefas
CREATE TABLE IF NOT EXISTS tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  titulo TEXT NOT NULL,
  descricao TEXT,
  prioridade TEXT NOT NULL DEFAULT 'normal' CHECK (prioridade IN ('baixa', 'normal', 'alta', 'urgente')),
  status TEXT NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente', 'em_andamento', 'concluida', 'cancelada')),
  -- Atribuição
  assigned_to UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Prazos
  due_date TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  -- Vínculos opcionais
  cliente_id UUID REFERENCES clientes(id) ON DELETE SET NULL,
  conteudo_id UUID REFERENCES conteudos(id) ON DELETE SET NULL,
  solicitacao_id UUID REFERENCES solicitacoes(id) ON DELETE SET NULL,
  -- Metadados
  tags TEXT[] DEFAULT '{}',
  checklist JSONB DEFAULT '[]',
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_tasks_org_id ON tasks(org_id);
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_to ON tasks(assigned_to);
CREATE INDEX IF NOT EXISTS idx_tasks_created_by ON tasks(created_by);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON tasks(due_date);
CREATE INDEX IF NOT EXISTS idx_tasks_cliente_id ON tasks(cliente_id);
CREATE INDEX IF NOT EXISTS idx_tasks_conteudo_id ON tasks(conteudo_id);

-- Comentários de tarefa (opcional, para futuro)
CREATE TABLE IF NOT EXISTS task_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  org_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  text TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_task_comments_task_id ON task_comments(task_id);

-- RLS Policies
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_comments ENABLE ROW LEVEL SECURITY;

-- Política: membros da org podem ver todas as tarefas da org
DROP POLICY IF EXISTS "Members can view org tasks" ON tasks;
CREATE POLICY "Members can view org tasks" ON tasks
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM members 
      WHERE members.org_id = tasks.org_id 
      AND members.user_id = auth.uid()
    )
  );

-- Política: membros podem criar tarefas
DROP POLICY IF EXISTS "Members can create tasks" ON tasks;
CREATE POLICY "Members can create tasks" ON tasks
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM members 
      WHERE members.org_id = tasks.org_id 
      AND members.user_id = auth.uid()
    )
  );

-- Política: membros podem atualizar tarefas (atribuídas a eles ou se tiverem permissão full)
DROP POLICY IF EXISTS "Members can update tasks" ON tasks;
CREATE POLICY "Members can update tasks" ON tasks
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM members 
      WHERE members.org_id = tasks.org_id 
      AND members.user_id = auth.uid()
    )
  );

-- Política: apenas admin/gestor podem deletar tarefas
DROP POLICY IF EXISTS "Admins can delete tasks" ON tasks;
CREATE POLICY "Admins can delete tasks" ON tasks
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM members 
      WHERE members.org_id = tasks.org_id 
      AND members.user_id = auth.uid()
      AND members.role IN ('admin', 'gestor')
    )
  );

-- Políticas para comentários
DROP POLICY IF EXISTS "Members can view task comments" ON task_comments;
CREATE POLICY "Members can view task comments" ON task_comments
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM members 
      WHERE members.org_id = task_comments.org_id 
      AND members.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Members can create task comments" ON task_comments;

CREATE POLICY "Members can create task comments" ON task_comments
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM members 
      WHERE members.org_id = task_comments.org_id 
      AND members.user_id = auth.uid()
    )
  );

-- Trigger para updated_at
CREATE OR REPLACE FUNCTION update_tasks_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_tasks_updated_at ON tasks;
DROP TRIGGER IF EXISTS trigger_tasks_updated_at ON tasks;
CREATE TRIGGER trigger_tasks_updated_at
  BEFORE UPDATE ON tasks
  FOR EACH ROW
  EXECUTE FUNCTION update_tasks_updated_at();


-- ============================================================
-- SOURCE: supabase/migrations/20260206_link_tracking.sql
-- ============================================================

-- Adicionar campos de tracking nos links de aprovação
ALTER TABLE aprovacoes_links 
ADD COLUMN IF NOT EXISTS last_viewed_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS view_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS views JSONB DEFAULT '[]'::jsonb;

-- Campos de feedback no conteúdo
ALTER TABLE conteudos 
ADD COLUMN IF NOT EXISTS comentario_cliente TEXT,
ADD COLUMN IF NOT EXISTS cliente_nome_feedback TEXT;

-- Índice para busca por links visualizados
CREATE INDEX IF NOT EXISTS idx_aprovacoes_links_viewed ON aprovacoes_links(last_viewed_at) WHERE last_viewed_at IS NOT NULL;


-- ============================================================
-- SOURCE: supabase/migrations/20260212_campanha_notificacoes.sql
-- ============================================================

-- =====================================================
-- MIGRATION: Sistema de Notificações de Campanhas
-- Data: 12/02/2026
-- Descrição: Notificações automáticas para campanhas
-- =====================================================

-- =====================================================
-- TABELA: campanha_notificacoes
-- =====================================================

CREATE TABLE IF NOT EXISTS campanha_notificacoes (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  campanha_id uuid NOT NULL REFERENCES campanhas(id) ON DELETE CASCADE,
  org_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  
  -- Tipo de notificação
  tipo varchar(50) NOT NULL,  -- inicio_proximo, prazo_vencendo, status_alterado, progresso_baixo
  
  -- Conteúdo
  titulo varchar(255) NOT NULL,
  mensagem text NOT NULL,
  
  -- Agendamento
  enviar_em timestamptz NOT NULL,
  enviada boolean DEFAULT false,
  enviada_em timestamptz,
  
  -- Configuração
  canal varchar(50) DEFAULT 'app',  -- app, email, push
  prioridade int DEFAULT 2,  -- 1=baixa, 2=média, 3=alta
  
  -- Metadados
  metadata jsonb,
  created_at timestamptz DEFAULT now()
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_campanha_notif_campanha ON campanha_notificacoes(campanha_id);
CREATE INDEX IF NOT EXISTS idx_campanha_notif_enviar ON campanha_notificacoes(enviar_em) WHERE enviada = false;
CREATE INDEX IF NOT EXISTS idx_campanha_notif_org ON campanha_notificacoes(org_id);

-- RLS
ALTER TABLE campanha_notificacoes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "campanha_notif_select" ON campanha_notificacoes;
DROP POLICY IF EXISTS "campanha_notif_select" ON campanha_notificacoes;
CREATE POLICY "campanha_notif_select" ON campanha_notificacoes
  FOR SELECT USING (
    org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanha_notif_insert" ON campanha_notificacoes;
DROP POLICY IF EXISTS "campanha_notif_insert" ON campanha_notificacoes;
CREATE POLICY "campanha_notif_insert" ON campanha_notificacoes
  FOR INSERT WITH CHECK (
    org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
  );

-- =====================================================
-- FUNÇÃO: Criar notificações para uma campanha
-- =====================================================

CREATE OR REPLACE FUNCTION criar_notificacoes_campanha(p_campanha_id uuid)
RETURNS void AS $$
DECLARE
  v_campanha RECORD;
  v_data_inicio date;
  v_data_fim date;
BEGIN
  -- Buscar dados da campanha
  SELECT * INTO v_campanha
  FROM campanhas
  WHERE id = p_campanha_id;
  
  IF NOT FOUND THEN
    RETURN;
  END IF;
  
  -- Calcular datas aproximadas
  v_data_inicio := make_date(v_campanha.ano, v_campanha.mes_inicio, 1);
  v_data_fim := (make_date(v_campanha.ano, v_campanha.mes_fim, 1) + interval '1 month - 1 day')::date;
  
  -- Limpar notificações antigas não enviadas
  DELETE FROM campanha_notificacoes
  WHERE campanha_id = p_campanha_id
    AND enviada = false;
  
  -- 1. Notificação 7 dias antes do início
  IF v_data_inicio - interval '7 days' > CURRENT_DATE THEN
    INSERT INTO campanha_notificacoes (
      campanha_id, org_id, tipo, titulo, mensagem, enviar_em, prioridade
    ) VALUES (
      p_campanha_id,
      v_campanha.org_id,
      'inicio_proximo',
      'Campanha começa em 7 dias',
      format('A campanha "%s" começa em 7 dias. Verifique se tudo está preparado!', v_campanha.nome),
      v_data_inicio - interval '7 days',
      2
    );
  END IF;
  
  -- 2. Notificação no dia do início
  IF v_data_inicio >= CURRENT_DATE THEN
    INSERT INTO campanha_notificacoes (
      campanha_id, org_id, tipo, titulo, mensagem, enviar_em, prioridade
    ) VALUES (
      p_campanha_id,
      v_campanha.org_id,
      'inicio_proximo',
      'Campanha iniciou hoje!',
      format('A campanha "%s" começou hoje. Bora executar! 🚀', v_campanha.nome),
      v_data_inicio,
      3
    );
  END IF;
  
  -- 3. Notificação 7 dias antes do fim
  IF v_data_fim - interval '7 days' > CURRENT_DATE THEN
    INSERT INTO campanha_notificacoes (
      campanha_id, org_id, tipo, titulo, mensagem, enviar_em, prioridade
    ) VALUES (
      p_campanha_id,
      v_campanha.org_id,
      'prazo_vencendo',
      'Campanha termina em 7 dias',
      format('A campanha "%s" termina em 7 dias. Verifique o progresso!', v_campanha.nome),
      v_data_fim - interval '7 days',
      2
    );
  END IF;
  
  -- 4. Notificação no último dia
  IF v_data_fim >= CURRENT_DATE THEN
    INSERT INTO campanha_notificacoes (
      campanha_id, org_id, tipo, titulo, mensagem, enviar_em, prioridade
    ) VALUES (
      p_campanha_id,
      v_campanha.org_id,
      'prazo_vencendo',
      'Último dia da campanha!',
      format('Hoje é o último dia da campanha "%s". Finalize tudo!', v_campanha.nome),
      v_data_fim,
      3
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- TRIGGER: Criar notificações ao criar/atualizar campanha
-- =====================================================

CREATE OR REPLACE FUNCTION trigger_criar_notificacoes_campanha()
RETURNS TRIGGER AS $$
BEGIN
  -- Só criar notificações se a campanha não estiver cancelada ou concluída
  IF NEW.status NOT IN ('cancelada', 'concluida') THEN
    PERFORM criar_notificacoes_campanha(NEW.id);
  ELSE
    -- Se cancelada/concluída, remover notificações pendentes
    DELETE FROM campanha_notificacoes
    WHERE campanha_id = NEW.id
      AND enviada = false;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS criar_notificacoes_on_campanha ON campanhas;
DROP TRIGGER IF EXISTS criar_notificacoes_on_campanha ON campanhas;
CREATE TRIGGER criar_notificacoes_on_campanha
  AFTER INSERT OR UPDATE OF mes_inicio, mes_fim, ano, status ON campanhas
  FOR EACH ROW
  EXECUTE FUNCTION trigger_criar_notificacoes_campanha();

-- =====================================================
-- VIEW: Notificações pendentes para envio
-- =====================================================

CREATE OR REPLACE VIEW v_notificacoes_pendentes AS
SELECT 
  n.*,
  c.nome as campanha_nome,
  c.tipo as campanha_tipo,
  c.cor as campanha_cor,
  cli.nome as cliente_nome,
  cli.slug as cliente_slug
FROM campanha_notificacoes n
JOIN campanhas c ON n.campanha_id = c.id
JOIN clientes cli ON c.cliente_id = cli.id
WHERE n.enviada = false
  AND n.enviar_em <= CURRENT_TIMESTAMP
ORDER BY n.prioridade DESC, n.enviar_em ASC;

-- =====================================================
-- FUNÇÃO: Marcar notificação como enviada
-- =====================================================

CREATE OR REPLACE FUNCTION marcar_notificacao_enviada(p_notificacao_id uuid)
RETURNS void AS $$
BEGIN
  UPDATE campanha_notificacoes
  SET enviada = true,
      enviada_em = now()
  WHERE id = p_notificacao_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- GRANTS
-- =====================================================

GRANT SELECT ON v_notificacoes_pendentes TO authenticated;
GRANT EXECUTE ON FUNCTION criar_notificacoes_campanha TO authenticated;
GRANT EXECUTE ON FUNCTION marcar_notificacao_enviada TO authenticated;

-- =====================================================
-- FIM DA MIGRATION
-- =====================================================


-- ============================================================
-- SOURCE: supabase/migrations/20260212_campanha_sync.sql
-- ============================================================

-- =====================================================
-- MIGRATION: Sincronização Campanhas <-> Conteúdos
-- Data: 12/02/2026
-- Descrição: Funções para sincronizar progresso
-- =====================================================

-- =====================================================
-- FUNÇÃO: Calcular progresso da campanha
-- Baseado nos conteúdos vinculados
-- =====================================================

CREATE OR REPLACE FUNCTION calcular_progresso_campanha(p_campanha_id uuid)
RETURNS int AS $$
DECLARE
  v_total int;
  v_publicados int;
  v_progresso int;
BEGIN
  -- Contar total de conteúdos vinculados
  SELECT COUNT(*) INTO v_total
  FROM campanha_conteudos
  WHERE campanha_id = p_campanha_id;
  
  -- Se não há conteúdos, retorna 0
  IF v_total = 0 THEN
    RETURN 0;
  END IF;
  
  -- Contar conteúdos publicados
  SELECT COUNT(*) INTO v_publicados
  FROM campanha_conteudos cc
  JOIN conteudos c ON cc.conteudo_id = c.id
  WHERE cc.campanha_id = p_campanha_id
    AND c.status = 'publicado';
  
  -- Calcular percentual
  v_progresso := ROUND((v_publicados::numeric / v_total) * 100);
  
  RETURN v_progresso;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- FUNÇÃO: Atualizar progresso da campanha
-- Chamada manualmente ou por trigger
-- =====================================================

CREATE OR REPLACE FUNCTION atualizar_progresso_campanha(p_campanha_id uuid)
RETURNS void AS $$
DECLARE
  v_progresso int;
  v_status varchar(30);
BEGIN
  -- Calcular novo progresso
  v_progresso := calcular_progresso_campanha(p_campanha_id);
  
  -- Determinar status baseado no progresso
  SELECT status INTO v_status
  FROM campanhas
  WHERE id = p_campanha_id;
  
  -- Se progresso é 100% e status é em_andamento, marcar como concluída
  IF v_progresso = 100 AND v_status = 'em_andamento' THEN
    UPDATE campanhas
    SET progresso = v_progresso, 
        status = 'concluida',
        updated_at = now()
    WHERE id = p_campanha_id;
  ELSE
    UPDATE campanhas
    SET progresso = v_progresso,
        updated_at = now()
    WHERE id = p_campanha_id;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- TRIGGER: Atualizar progresso quando conteúdo muda
-- =====================================================

CREATE OR REPLACE FUNCTION trigger_sync_campanha_progresso()
RETURNS TRIGGER AS $$
DECLARE
  v_campanha_id uuid;
BEGIN
  -- Encontrar campanhas vinculadas ao conteúdo
  FOR v_campanha_id IN 
    SELECT DISTINCT campanha_id 
    FROM campanha_conteudos 
    WHERE conteudo_id = COALESCE(NEW.id, OLD.id)
  LOOP
    PERFORM atualizar_progresso_campanha(v_campanha_id);
  END LOOP;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Criar trigger na tabela conteudos (se status mudar)
DROP TRIGGER IF EXISTS sync_campanha_on_conteudo_change ON conteudos;
DROP TRIGGER IF EXISTS sync_campanha_on_conteudo_change ON conteudos;
CREATE TRIGGER sync_campanha_on_conteudo_change
  AFTER UPDATE OF status ON conteudos
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION trigger_sync_campanha_progresso();

-- =====================================================
-- TRIGGER: Atualizar progresso quando vínculo muda
-- =====================================================

CREATE OR REPLACE FUNCTION trigger_sync_campanha_on_vinculo()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
    PERFORM atualizar_progresso_campanha(NEW.campanha_id);
  END IF;
  
  IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
    IF OLD.campanha_id IS DISTINCT FROM NEW.campanha_id THEN
      PERFORM atualizar_progresso_campanha(OLD.campanha_id);
    END IF;
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS sync_campanha_on_vinculo_change ON campanha_conteudos;
DROP TRIGGER IF EXISTS sync_campanha_on_vinculo_change ON campanha_conteudos;
CREATE TRIGGER sync_campanha_on_vinculo_change
  AFTER INSERT OR UPDATE OR DELETE ON campanha_conteudos
  FOR EACH ROW
  EXECUTE FUNCTION trigger_sync_campanha_on_vinculo();

-- =====================================================
-- VIEW: Campanhas ativas do mês atual
-- Para uso no dashboard
-- =====================================================

CREATE OR REPLACE VIEW v_campanhas_ativas AS
SELECT 
  c.*,
  cli.nome as cliente_nome,
  cli.slug as cliente_slug,
  cli.logo_url as cliente_logo,
  COALESCE(stats.total_conteudos, 0) as total_conteudos,
  COALESCE(stats.conteudos_publicados, 0) as conteudos_publicados
FROM campanhas c
JOIN clientes cli ON c.cliente_id = cli.id
LEFT JOIN LATERAL (
  SELECT 
    COUNT(cc.id) as total_conteudos,
    COUNT(CASE WHEN cont.status = 'publicado' THEN 1 END) as conteudos_publicados
  FROM campanha_conteudos cc
  LEFT JOIN conteudos cont ON cc.conteudo_id = cont.id
  WHERE cc.campanha_id = c.id
) stats ON true
WHERE c.status IN ('planejada', 'em_andamento')
  AND c.ano = EXTRACT(YEAR FROM CURRENT_DATE)
  AND EXTRACT(MONTH FROM CURRENT_DATE) BETWEEN c.mes_inicio AND c.mes_fim;

-- =====================================================
-- VIEW: Próximas campanhas (próximo mês)
-- =====================================================

CREATE OR REPLACE VIEW v_campanhas_proximas AS
SELECT 
  c.*,
  cli.nome as cliente_nome,
  cli.slug as cliente_slug,
  cli.logo_url as cliente_logo
FROM campanhas c
JOIN clientes cli ON c.cliente_id = cli.id
WHERE c.status = 'planejada'
  AND c.ano = EXTRACT(YEAR FROM CURRENT_DATE)
  AND c.mes_inicio = EXTRACT(MONTH FROM CURRENT_DATE) + 1;

-- =====================================================
-- GRANTS
-- =====================================================

GRANT EXECUTE ON FUNCTION calcular_progresso_campanha TO authenticated;
GRANT EXECUTE ON FUNCTION atualizar_progresso_campanha TO authenticated;
GRANT SELECT ON v_campanhas_ativas TO authenticated;
GRANT SELECT ON v_campanhas_proximas TO authenticated;

-- =====================================================
-- FIM DA MIGRATION
-- =====================================================


-- ============================================================
-- SOURCE: supabase/migrations/20260212_planejamento_anual.sql
-- ============================================================

-- =====================================================
-- MIGRATION: Módulo de Planejamento Anual
-- Data: 12/02/2026
-- Descrição: Cria tabelas e estruturas para campanhas
-- =====================================================

-- =====================================================
-- TASK 1.1: TABELA campanhas
-- =====================================================

CREATE TABLE IF NOT EXISTS campanhas (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  cliente_id uuid NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
  
  -- Identificação
  nome varchar(255) NOT NULL,
  slug varchar(255),
  descricao text,
  objetivo text,
  acoes_planejadas text,
  
  -- Período
  ano int NOT NULL,
  mes_inicio int NOT NULL CHECK (mes_inicio >= 1 AND mes_inicio <= 12),
  mes_fim int NOT NULL CHECK (mes_fim >= 1 AND mes_fim <= 12),
  data_inicio date,
  data_fim date,
  
  -- Categorização
  tipo varchar(50) DEFAULT 'campanha',
  cor varchar(7) DEFAULT '#3B82F6',
  icone varchar(50),
  prioridade int DEFAULT 2 CHECK (prioridade >= 1 AND prioridade <= 3),
  
  -- Metas e Orçamento
  meta_principal text,
  meta_secundaria text,
  kpi_esperado jsonb,
  orcamento decimal(12,2),
  
  -- Status e Progresso
  status varchar(30) DEFAULT 'planejada',
  progresso int DEFAULT 0 CHECK (progresso >= 0 AND progresso <= 100),
  
  -- Relacionamentos
  responsavel_id uuid REFERENCES auth.users(id),
  
  -- Metadados
  created_by uuid REFERENCES auth.users(id),
  updated_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Comentários
COMMENT ON TABLE campanhas IS 'Campanhas e ações planejadas por cliente/ano';
COMMENT ON COLUMN campanhas.kpi_esperado IS 'KPIs esperados em formato JSON';
COMMENT ON COLUMN campanhas.acoes_planejadas IS 'Lista de ações em markdown';
COMMENT ON COLUMN campanhas.tipo IS 'Tipos: campanha, data_comemorativa, lancamento, institucional, promocao, awareness';
COMMENT ON COLUMN campanhas.status IS 'Status: planejada, em_andamento, pausada, concluida, cancelada';

-- =====================================================
-- TASK 1.2: TABELA campanha_conteudos
-- =====================================================

CREATE TABLE IF NOT EXISTS campanha_conteudos (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  campanha_id uuid NOT NULL REFERENCES campanhas(id) ON DELETE CASCADE,
  conteudo_id uuid NOT NULL REFERENCES conteudos(id) ON DELETE CASCADE,
  ordem int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  
  UNIQUE(campanha_id, conteudo_id)
);

COMMENT ON TABLE campanha_conteudos IS 'Relacionamento N:N entre campanhas e conteúdos';

-- =====================================================
-- TASK 1.3: TABELA campanha_historico
-- =====================================================

CREATE TABLE IF NOT EXISTS campanha_historico (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  campanha_id uuid NOT NULL REFERENCES campanhas(id) ON DELETE CASCADE,
  acao varchar(50) NOT NULL,
  campo_alterado varchar(100),
  valor_anterior text,
  valor_novo text,
  user_id uuid REFERENCES auth.users(id),
  user_email varchar(255),
  created_at timestamptz DEFAULT now()
);

COMMENT ON TABLE campanha_historico IS 'Log de alterações nas campanhas para auditoria';

-- =====================================================
-- TASK 1.4: ÍNDICES
-- =====================================================

-- Índices principais
CREATE INDEX IF NOT EXISTS idx_campanhas_org ON campanhas(org_id);
CREATE INDEX IF NOT EXISTS idx_campanhas_cliente ON campanhas(cliente_id);
CREATE INDEX IF NOT EXISTS idx_campanhas_ano ON campanhas(ano);
CREATE INDEX IF NOT EXISTS idx_campanhas_status ON campanhas(status);
CREATE INDEX IF NOT EXISTS idx_campanhas_tipo ON campanhas(tipo);
CREATE INDEX IF NOT EXISTS idx_campanhas_periodo ON campanhas(ano, mes_inicio, mes_fim);
CREATE INDEX IF NOT EXISTS idx_campanhas_cliente_ano ON campanhas(cliente_id, ano);
CREATE INDEX IF NOT EXISTS idx_campanhas_created ON campanhas(created_at DESC);

-- Índices para relacionamentos
CREATE INDEX IF NOT EXISTS idx_campanha_conteudos_campanha ON campanha_conteudos(campanha_id);
CREATE INDEX IF NOT EXISTS idx_campanha_conteudos_conteudo ON campanha_conteudos(conteudo_id);

-- Índices para histórico
CREATE INDEX IF NOT EXISTS idx_campanha_historico_campanha ON campanha_historico(campanha_id);
CREATE INDEX IF NOT EXISTS idx_campanha_historico_created ON campanha_historico(created_at DESC);

-- Índice para busca por texto
CREATE INDEX IF NOT EXISTS idx_campanhas_nome_gin ON campanhas USING gin(to_tsvector('portuguese', nome));

-- =====================================================
-- TASK 1.5: RLS (Row Level Security)
-- =====================================================

-- Habilitar RLS
ALTER TABLE campanhas ENABLE ROW LEVEL SECURITY;
ALTER TABLE campanha_conteudos ENABLE ROW LEVEL SECURITY;
ALTER TABLE campanha_historico ENABLE ROW LEVEL SECURITY;

-- Políticas para campanhas
DROP POLICY IF EXISTS "campanhas_select_policy" ON campanhas;
DROP POLICY IF EXISTS "campanhas_select_policy" ON campanhas;
CREATE POLICY "campanhas_select_policy" ON campanhas
  FOR SELECT USING (
    org_id IN (SELECT org_id FROM org_members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_insert_policy" ON campanhas;
DROP POLICY IF EXISTS "campanhas_insert_policy" ON campanhas;
CREATE POLICY "campanhas_insert_policy" ON campanhas
  FOR INSERT WITH CHECK (
    org_id IN (SELECT org_id FROM org_members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_update_policy" ON campanhas;
DROP POLICY IF EXISTS "campanhas_update_policy" ON campanhas;
CREATE POLICY "campanhas_update_policy" ON campanhas
  FOR UPDATE USING (
    org_id IN (SELECT org_id FROM org_members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_delete_policy" ON campanhas;
DROP POLICY IF EXISTS "campanhas_delete_policy" ON campanhas;
CREATE POLICY "campanhas_delete_policy" ON campanhas
  FOR DELETE USING (
    org_id IN (SELECT org_id FROM org_members WHERE user_id = auth.uid())
  );

-- Políticas para campanha_conteudos
DROP POLICY IF EXISTS "campanha_conteudos_select_policy" ON campanha_conteudos;
DROP POLICY IF EXISTS "campanha_conteudos_select_policy" ON campanha_conteudos;
CREATE POLICY "campanha_conteudos_select_policy" ON campanha_conteudos
  FOR SELECT USING (
    campanha_id IN (
      SELECT id FROM campanhas WHERE org_id IN (
        SELECT org_id FROM org_members WHERE user_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS "campanha_conteudos_all_policy" ON campanha_conteudos;
DROP POLICY IF EXISTS "campanha_conteudos_all_policy" ON campanha_conteudos;
CREATE POLICY "campanha_conteudos_all_policy" ON campanha_conteudos
  FOR ALL USING (
    campanha_id IN (
      SELECT id FROM campanhas WHERE org_id IN (
        SELECT org_id FROM org_members WHERE user_id = auth.uid()
      )
    )
  );

-- Políticas para campanha_historico
DROP POLICY IF EXISTS "campanha_historico_select_policy" ON campanha_historico;
DROP POLICY IF EXISTS "campanha_historico_select_policy" ON campanha_historico;
CREATE POLICY "campanha_historico_select_policy" ON campanha_historico
  FOR SELECT USING (
    campanha_id IN (
      SELECT id FROM campanhas WHERE org_id IN (
        SELECT org_id FROM org_members WHERE user_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS "campanha_historico_insert_policy" ON campanha_historico;
DROP POLICY IF EXISTS "campanha_historico_insert_policy" ON campanha_historico;
CREATE POLICY "campanha_historico_insert_policy" ON campanha_historico
  FOR INSERT WITH CHECK (
    campanha_id IN (
      SELECT id FROM campanhas WHERE org_id IN (
        SELECT org_id FROM org_members WHERE user_id = auth.uid()
      )
    )
  );

-- =====================================================
-- TASK 1.6: TRIGGERS
-- =====================================================

-- Trigger para atualizar updated_at
CREATE OR REPLACE FUNCTION update_campanhas_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS campanhas_updated_at ON campanhas;
DROP TRIGGER IF EXISTS campanhas_updated_at ON campanhas;
CREATE TRIGGER campanhas_updated_at
  BEFORE UPDATE ON campanhas
  FOR EACH ROW
  EXECUTE FUNCTION update_campanhas_updated_at();

-- Trigger para gerar slug automático
CREATE OR REPLACE FUNCTION generate_campanha_slug()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.slug IS NULL OR NEW.slug = '' THEN
    NEW.slug = lower(
      regexp_replace(
        translate(NEW.nome, 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'),
        '[^a-zA-Z0-9]+', '-', 'g'
      )
    );
    -- Remove hífens duplicados e nas pontas
    NEW.slug = regexp_replace(NEW.slug, '-+', '-', 'g');
    NEW.slug = trim(both '-' from NEW.slug);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS campanhas_generate_slug ON campanhas;
DROP TRIGGER IF EXISTS campanhas_generate_slug ON campanhas;
CREATE TRIGGER campanhas_generate_slug
  BEFORE INSERT OR UPDATE OF nome ON campanhas
  FOR EACH ROW
  EXECUTE FUNCTION generate_campanha_slug();

-- Trigger para log de histórico
CREATE OR REPLACE FUNCTION log_campanha_changes()
RETURNS TRIGGER AS $$
DECLARE
  v_user_email varchar(255);
BEGIN
  -- Buscar email do usuário
  SELECT email INTO v_user_email FROM auth.users WHERE id = auth.uid();
  
  IF TG_OP = 'INSERT' THEN
    INSERT INTO campanha_historico (campanha_id, acao, user_id, user_email)
    VALUES (NEW.id, 'created', auth.uid(), v_user_email);
    
  ELSIF TG_OP = 'UPDATE' THEN
    -- Log mudança de status
    IF OLD.status IS DISTINCT FROM NEW.status THEN
      INSERT INTO campanha_historico (campanha_id, acao, campo_alterado, valor_anterior, valor_novo, user_id, user_email)
      VALUES (NEW.id, 'status_changed', 'status', OLD.status, NEW.status, auth.uid(), v_user_email);
    END IF;
    
    -- Log mudança de nome
    IF OLD.nome IS DISTINCT FROM NEW.nome THEN
      INSERT INTO campanha_historico (campanha_id, acao, campo_alterado, valor_anterior, valor_novo, user_id, user_email)
      VALUES (NEW.id, 'updated', 'nome', OLD.nome, NEW.nome, auth.uid(), v_user_email);
    END IF;
    
    -- Log mudança de período
    IF OLD.mes_inicio IS DISTINCT FROM NEW.mes_inicio OR OLD.mes_fim IS DISTINCT FROM NEW.mes_fim THEN
      INSERT INTO campanha_historico (campanha_id, acao, campo_alterado, valor_anterior, valor_novo, user_id, user_email)
      VALUES (
        NEW.id, 
        'updated', 
        'periodo', 
        OLD.mes_inicio || '-' || OLD.mes_fim, 
        NEW.mes_inicio || '-' || NEW.mes_fim, 
        auth.uid(), 
        v_user_email
      );
    END IF;
    
    -- Log mudança de progresso significativa (a cada 25%)
    IF OLD.progresso IS DISTINCT FROM NEW.progresso AND 
       (NEW.progresso = 0 OR NEW.progresso = 25 OR NEW.progresso = 50 OR NEW.progresso = 75 OR NEW.progresso = 100) THEN
      INSERT INTO campanha_historico (campanha_id, acao, campo_alterado, valor_anterior, valor_novo, user_id, user_email)
      VALUES (NEW.id, 'updated', 'progresso', OLD.progresso::text, NEW.progresso::text, auth.uid(), v_user_email);
    END IF;
    
  ELSIF TG_OP = 'DELETE' THEN
    -- Não podemos inserir no histórico se a campanha foi deletada (cascade)
    -- O histórico será deletado junto
    NULL;
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS campanhas_audit_log ON campanhas;
DROP TRIGGER IF EXISTS campanhas_audit_log ON campanhas;
CREATE TRIGGER campanhas_audit_log
  AFTER INSERT OR UPDATE ON campanhas
  FOR EACH ROW
  EXECUTE FUNCTION log_campanha_changes();

-- =====================================================
-- TASK 1.7: VIEWS
-- =====================================================

-- View: Campanhas com estatísticas de conteúdos
CREATE OR REPLACE VIEW v_campanhas_stats AS
SELECT 
  c.*,
  COALESCE(stats.total_conteudos, 0) as total_conteudos,
  COALESCE(stats.conteudos_publicados, 0) as conteudos_publicados,
  CASE 
    WHEN COALESCE(stats.total_conteudos, 0) = 0 THEN 0
    ELSE ROUND(COALESCE(stats.conteudos_publicados, 0)::numeric / stats.total_conteudos * 100, 0)
  END as percentual_publicado,
  cli.nome as cliente_nome,
  cli.slug as cliente_slug
FROM campanhas c
LEFT JOIN clientes cli ON c.cliente_id = cli.id
LEFT JOIN LATERAL (
  SELECT 
    COUNT(cc.id) as total_conteudos,
    COUNT(CASE WHEN cont.status = 'publicado' THEN 1 END) as conteudos_publicados
  FROM campanha_conteudos cc
  LEFT JOIN conteudos cont ON cc.conteudo_id = cont.id
  WHERE cc.campanha_id = c.id
) stats ON true;

-- View: Resumo anual por cliente
CREATE OR REPLACE VIEW v_planejamento_anual AS
SELECT 
  cliente_id,
  ano,
  COUNT(*) as total_campanhas,
  COUNT(CASE WHEN status = 'planejada' THEN 1 END) as planejadas,
  COUNT(CASE WHEN status = 'em_andamento' THEN 1 END) as em_andamento,
  COUNT(CASE WHEN status = 'pausada' THEN 1 END) as pausadas,
  COUNT(CASE WHEN status = 'concluida' THEN 1 END) as concluidas,
  COUNT(CASE WHEN status = 'cancelada' THEN 1 END) as canceladas,
  COALESCE(SUM(orcamento), 0) as orcamento_total,
  ROUND(AVG(progresso), 0) as progresso_medio
FROM campanhas
GROUP BY cliente_id, ano;

-- View: Campanhas por mês (para timeline)
CREATE OR REPLACE VIEW v_campanhas_timeline AS
SELECT 
  c.id,
  c.cliente_id,
  c.nome,
  c.tipo,
  c.cor,
  c.icone,
  c.status,
  c.progresso,
  c.prioridade,
  c.ano,
  c.mes_inicio,
  c.mes_fim,
  (c.mes_fim - c.mes_inicio + 1) as duracao_meses,
  c.meta_principal,
  cli.nome as cliente_nome
FROM campanhas c
JOIN clientes cli ON c.cliente_id = cli.id
ORDER BY c.ano, c.mes_inicio, c.prioridade DESC;

-- =====================================================
-- TASK 1.8: FUNÇÃO PARA VERIFICAR CONFLITOS
-- =====================================================

CREATE OR REPLACE FUNCTION get_campanhas_do_mes(
  p_cliente_id uuid,
  p_ano int,
  p_mes int
)
RETURNS TABLE (
  id uuid, 
  nome varchar, 
  tipo varchar,
  cor varchar,
  icone varchar,
  status varchar,
  mes_inicio int, 
  mes_fim int
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.id, 
    c.nome, 
    c.tipo,
    c.cor,
    c.icone,
    c.status,
    c.mes_inicio, 
    c.mes_fim
  FROM campanhas c
  WHERE c.cliente_id = p_cliente_id
    AND c.ano = p_ano
    AND p_mes BETWEEN c.mes_inicio AND c.mes_fim
  ORDER BY c.prioridade DESC, c.mes_inicio;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Função para buscar campanhas que conflitam com um período
CREATE OR REPLACE FUNCTION get_campanhas_conflitantes(
  p_cliente_id uuid,
  p_ano int,
  p_mes_inicio int,
  p_mes_fim int,
  p_excluir_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid, 
  nome varchar, 
  mes_inicio int, 
  mes_fim int
) AS $$
BEGIN
  RETURN QUERY
  SELECT c.id, c.nome, c.mes_inicio, c.mes_fim
  FROM campanhas c
  WHERE c.cliente_id = p_cliente_id
    AND c.ano = p_ano
    AND c.id IS DISTINCT FROM p_excluir_id
    AND (
      (p_mes_inicio BETWEEN c.mes_inicio AND c.mes_fim)
      OR (p_mes_fim BETWEEN c.mes_inicio AND c.mes_fim)
      OR (c.mes_inicio BETWEEN p_mes_inicio AND p_mes_fim)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- GRANTS (permissões)
-- =====================================================

-- Grants para as views
GRANT SELECT ON v_campanhas_stats TO authenticated;
GRANT SELECT ON v_planejamento_anual TO authenticated;
GRANT SELECT ON v_campanhas_timeline TO authenticated;

-- Grants para as funções
GRANT EXECUTE ON FUNCTION get_campanhas_do_mes TO authenticated;
GRANT EXECUTE ON FUNCTION get_campanhas_conflitantes TO authenticated;

-- =====================================================
-- FIM DA MIGRATION
-- =====================================================


-- ============================================================
-- SOURCE: supabase/migrations/20260212_planejamento_anual_v2.sql
-- ============================================================

-- =====================================================
-- MIGRATION: Módulo de Planejamento Anual (CORRIGIDA)
-- Data: 12/02/2026
-- Descrição: Cria tabelas e estruturas para campanhas
-- CORREÇÃO: Usa organization_members (não org_members)
-- =====================================================

-- =====================================================
-- TASK 1.1: TABELA campanhas
-- =====================================================

CREATE TABLE IF NOT EXISTS campanhas (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  cliente_id uuid NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
  
  -- Identificação
  nome varchar(255) NOT NULL,
  slug varchar(255),
  descricao text,
  objetivo text,
  acoes_planejadas text,
  
  -- Período
  ano int NOT NULL,
  mes_inicio int NOT NULL CHECK (mes_inicio >= 1 AND mes_inicio <= 12),
  mes_fim int NOT NULL CHECK (mes_fim >= 1 AND mes_fim <= 12),
  data_inicio date,
  data_fim date,
  
  -- Categorização
  tipo varchar(50) DEFAULT 'campanha',
  cor varchar(7) DEFAULT '#3B82F6',
  icone varchar(50),
  prioridade int DEFAULT 2 CHECK (prioridade >= 1 AND prioridade <= 3),
  
  -- Metas e Orçamento
  meta_principal text,
  meta_secundaria text,
  kpi_esperado jsonb,
  orcamento decimal(12,2),
  
  -- Status e Progresso
  status varchar(30) DEFAULT 'planejada',
  progresso int DEFAULT 0 CHECK (progresso >= 0 AND progresso <= 100),
  
  -- Relacionamentos
  responsavel_id uuid REFERENCES auth.users(id),
  
  -- Metadados
  created_by uuid REFERENCES auth.users(id),
  updated_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Comentários
COMMENT ON TABLE campanhas IS 'Campanhas e ações planejadas por cliente/ano';
COMMENT ON COLUMN campanhas.kpi_esperado IS 'KPIs esperados em formato JSON';
COMMENT ON COLUMN campanhas.acoes_planejadas IS 'Lista de ações em markdown';
COMMENT ON COLUMN campanhas.tipo IS 'Tipos: campanha, data_comemorativa, lancamento, institucional, promocao, awareness';
COMMENT ON COLUMN campanhas.status IS 'Status: planejada, em_andamento, pausada, concluida, cancelada';

-- =====================================================
-- TASK 1.2: TABELA campanha_conteudos
-- =====================================================

CREATE TABLE IF NOT EXISTS campanha_conteudos (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  campanha_id uuid NOT NULL REFERENCES campanhas(id) ON DELETE CASCADE,
  conteudo_id uuid NOT NULL REFERENCES conteudos(id) ON DELETE CASCADE,
  ordem int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  
  UNIQUE(campanha_id, conteudo_id)
);

COMMENT ON TABLE campanha_conteudos IS 'Relacionamento N:N entre campanhas e conteúdos';

-- =====================================================
-- TASK 1.3: TABELA campanha_historico
-- =====================================================

CREATE TABLE IF NOT EXISTS campanha_historico (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  campanha_id uuid NOT NULL REFERENCES campanhas(id) ON DELETE CASCADE,
  acao varchar(50) NOT NULL,
  campo_alterado varchar(100),
  valor_anterior text,
  valor_novo text,
  user_id uuid REFERENCES auth.users(id),
  user_email varchar(255),
  created_at timestamptz DEFAULT now()
);

COMMENT ON TABLE campanha_historico IS 'Log de alterações nas campanhas para auditoria';

-- =====================================================
-- TASK 1.4: ÍNDICES
-- =====================================================

-- Índices principais
CREATE INDEX IF NOT EXISTS idx_campanhas_org ON campanhas(organization_id);
CREATE INDEX IF NOT EXISTS idx_campanhas_cliente ON campanhas(cliente_id);
CREATE INDEX IF NOT EXISTS idx_campanhas_ano ON campanhas(ano);
CREATE INDEX IF NOT EXISTS idx_campanhas_status ON campanhas(status);
CREATE INDEX IF NOT EXISTS idx_campanhas_tipo ON campanhas(tipo);
CREATE INDEX IF NOT EXISTS idx_campanhas_periodo ON campanhas(ano, mes_inicio, mes_fim);
CREATE INDEX IF NOT EXISTS idx_campanhas_cliente_ano ON campanhas(cliente_id, ano);
CREATE INDEX IF NOT EXISTS idx_campanhas_created ON campanhas(created_at DESC);

-- Índices para relacionamentos
CREATE INDEX IF NOT EXISTS idx_campanha_conteudos_campanha ON campanha_conteudos(campanha_id);
CREATE INDEX IF NOT EXISTS idx_campanha_conteudos_conteudo ON campanha_conteudos(conteudo_id);

-- Índices para histórico
CREATE INDEX IF NOT EXISTS idx_campanha_historico_campanha ON campanha_historico(campanha_id);
CREATE INDEX IF NOT EXISTS idx_campanha_historico_created ON campanha_historico(created_at DESC);

-- Índice para busca por texto
CREATE INDEX IF NOT EXISTS idx_campanhas_nome_gin ON campanhas USING gin(to_tsvector('portuguese', nome));

-- =====================================================
-- TASK 1.5: RLS (Row Level Security)
-- =====================================================

-- Habilitar RLS
ALTER TABLE campanhas ENABLE ROW LEVEL SECURITY;
ALTER TABLE campanha_conteudos ENABLE ROW LEVEL SECURITY;
ALTER TABLE campanha_historico ENABLE ROW LEVEL SECURITY;

-- Políticas para campanhas
DROP POLICY IF EXISTS "campanhas_select_policy" ON campanhas;
DROP POLICY IF EXISTS "campanhas_select_policy" ON campanhas;
CREATE POLICY "campanhas_select_policy" ON campanhas
  FOR SELECT USING (
    organization_id IN (SELECT organization_id FROM organization_members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_insert_policy" ON campanhas;
DROP POLICY IF EXISTS "campanhas_insert_policy" ON campanhas;
CREATE POLICY "campanhas_insert_policy" ON campanhas
  FOR INSERT WITH CHECK (
    organization_id IN (SELECT organization_id FROM organization_members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_update_policy" ON campanhas;
DROP POLICY IF EXISTS "campanhas_update_policy" ON campanhas;
CREATE POLICY "campanhas_update_policy" ON campanhas
  FOR UPDATE USING (
    organization_id IN (SELECT organization_id FROM organization_members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_delete_policy" ON campanhas;
DROP POLICY IF EXISTS "campanhas_delete_policy" ON campanhas;
CREATE POLICY "campanhas_delete_policy" ON campanhas
  FOR DELETE USING (
    organization_id IN (SELECT organization_id FROM organization_members WHERE user_id = auth.uid())
  );

-- Políticas para campanha_conteudos
DROP POLICY IF EXISTS "campanha_conteudos_select_policy" ON campanha_conteudos;
DROP POLICY IF EXISTS "campanha_conteudos_select_policy" ON campanha_conteudos;
CREATE POLICY "campanha_conteudos_select_policy" ON campanha_conteudos
  FOR SELECT USING (
    campanha_id IN (
      SELECT id FROM campanhas WHERE organization_id IN (
        SELECT organization_id FROM organization_members WHERE user_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS "campanha_conteudos_all_policy" ON campanha_conteudos;
DROP POLICY IF EXISTS "campanha_conteudos_all_policy" ON campanha_conteudos;
CREATE POLICY "campanha_conteudos_all_policy" ON campanha_conteudos
  FOR ALL USING (
    campanha_id IN (
      SELECT id FROM campanhas WHERE organization_id IN (
        SELECT organization_id FROM organization_members WHERE user_id = auth.uid()
      )
    )
  );

-- Políticas para campanha_historico
DROP POLICY IF EXISTS "campanha_historico_select_policy" ON campanha_historico;
DROP POLICY IF EXISTS "campanha_historico_select_policy" ON campanha_historico;
CREATE POLICY "campanha_historico_select_policy" ON campanha_historico
  FOR SELECT USING (
    campanha_id IN (
      SELECT id FROM campanhas WHERE organization_id IN (
        SELECT organization_id FROM organization_members WHERE user_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS "campanha_historico_insert_policy" ON campanha_historico;
DROP POLICY IF EXISTS "campanha_historico_insert_policy" ON campanha_historico;
CREATE POLICY "campanha_historico_insert_policy" ON campanha_historico
  FOR INSERT WITH CHECK (
    campanha_id IN (
      SELECT id FROM campanhas WHERE organization_id IN (
        SELECT organization_id FROM organization_members WHERE user_id = auth.uid()
      )
    )
  );

-- =====================================================
-- TASK 1.6: TRIGGERS
-- =====================================================

-- Trigger para atualizar updated_at
CREATE OR REPLACE FUNCTION update_campanhas_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS campanhas_updated_at ON campanhas;
DROP TRIGGER IF EXISTS campanhas_updated_at ON campanhas;
CREATE TRIGGER campanhas_updated_at
  BEFORE UPDATE ON campanhas
  FOR EACH ROW
  EXECUTE FUNCTION update_campanhas_updated_at();

-- Trigger para gerar slug automático
CREATE OR REPLACE FUNCTION generate_campanha_slug()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.slug IS NULL OR NEW.slug = '' THEN
    NEW.slug = lower(
      regexp_replace(
        translate(NEW.nome, 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'),
        '[^a-zA-Z0-9]+', '-', 'g'
      )
    );
    -- Remove hífens duplicados e nas pontas
    NEW.slug = regexp_replace(NEW.slug, '-+', '-', 'g');
    NEW.slug = trim(both '-' from NEW.slug);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS campanhas_generate_slug ON campanhas;
DROP TRIGGER IF EXISTS campanhas_generate_slug ON campanhas;
CREATE TRIGGER campanhas_generate_slug
  BEFORE INSERT OR UPDATE OF nome ON campanhas
  FOR EACH ROW
  EXECUTE FUNCTION generate_campanha_slug();

-- Trigger para log de histórico
CREATE OR REPLACE FUNCTION log_campanha_changes()
RETURNS TRIGGER AS $$
DECLARE
  v_user_email varchar(255);
BEGIN
  -- Buscar email do usuário
  SELECT email INTO v_user_email FROM auth.users WHERE id = auth.uid();
  
  IF TG_OP = 'INSERT' THEN
    INSERT INTO campanha_historico (campanha_id, acao, user_id, user_email)
    VALUES (NEW.id, 'created', auth.uid(), v_user_email);
    
  ELSIF TG_OP = 'UPDATE' THEN
    -- Log mudança de status
    IF OLD.status IS DISTINCT FROM NEW.status THEN
      INSERT INTO campanha_historico (campanha_id, acao, campo_alterado, valor_anterior, valor_novo, user_id, user_email)
      VALUES (NEW.id, 'status_changed', 'status', OLD.status, NEW.status, auth.uid(), v_user_email);
    END IF;
    
    -- Log mudança de nome
    IF OLD.nome IS DISTINCT FROM NEW.nome THEN
      INSERT INTO campanha_historico (campanha_id, acao, campo_alterado, valor_anterior, valor_novo, user_id, user_email)
      VALUES (NEW.id, 'updated', 'nome', OLD.nome, NEW.nome, auth.uid(), v_user_email);
    END IF;
    
    -- Log mudança de período
    IF OLD.mes_inicio IS DISTINCT FROM NEW.mes_inicio OR OLD.mes_fim IS DISTINCT FROM NEW.mes_fim THEN
      INSERT INTO campanha_historico (campanha_id, acao, campo_alterado, valor_anterior, valor_novo, user_id, user_email)
      VALUES (
        NEW.id, 
        'updated', 
        'periodo', 
        OLD.mes_inicio || '-' || OLD.mes_fim, 
        NEW.mes_inicio || '-' || NEW.mes_fim, 
        auth.uid(), 
        v_user_email
      );
    END IF;
    
    -- Log mudança de progresso significativa (a cada 25%)
    IF OLD.progresso IS DISTINCT FROM NEW.progresso AND 
       (NEW.progresso = 0 OR NEW.progresso = 25 OR NEW.progresso = 50 OR NEW.progresso = 75 OR NEW.progresso = 100) THEN
      INSERT INTO campanha_historico (campanha_id, acao, campo_alterado, valor_anterior, valor_novo, user_id, user_email)
      VALUES (NEW.id, 'updated', 'progresso', OLD.progresso::text, NEW.progresso::text, auth.uid(), v_user_email);
    END IF;
    
  ELSIF TG_OP = 'DELETE' THEN
    NULL;
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS campanhas_audit_log ON campanhas;
DROP TRIGGER IF EXISTS campanhas_audit_log ON campanhas;
CREATE TRIGGER campanhas_audit_log
  AFTER INSERT OR UPDATE ON campanhas
  FOR EACH ROW
  EXECUTE FUNCTION log_campanha_changes();

-- =====================================================
-- TASK 1.7: VIEWS
-- =====================================================

-- View: Campanhas com estatísticas de conteúdos
CREATE OR REPLACE VIEW v_campanhas_stats AS
SELECT 
  c.*,
  COALESCE(stats.total_conteudos, 0) as total_conteudos,
  COALESCE(stats.conteudos_publicados, 0) as conteudos_publicados,
  CASE 
    WHEN COALESCE(stats.total_conteudos, 0) = 0 THEN 0
    ELSE ROUND(COALESCE(stats.conteudos_publicados, 0)::numeric / stats.total_conteudos * 100, 0)
  END as percentual_publicado,
  cli.nome as cliente_nome,
  cli.slug as cliente_slug
FROM campanhas c
LEFT JOIN clientes cli ON c.cliente_id = cli.id
LEFT JOIN LATERAL (
  SELECT 
    COUNT(cc.id) as total_conteudos,
    COUNT(CASE WHEN cont.status = 'publicado' THEN 1 END) as conteudos_publicados
  FROM campanha_conteudos cc
  LEFT JOIN conteudos cont ON cc.conteudo_id = cont.id
  WHERE cc.campanha_id = c.id
) stats ON true;

-- View: Resumo anual por cliente
CREATE OR REPLACE VIEW v_planejamento_anual AS
SELECT 
  cliente_id,
  ano,
  COUNT(*) as total_campanhas,
  COUNT(CASE WHEN status = 'planejada' THEN 1 END) as planejadas,
  COUNT(CASE WHEN status = 'em_andamento' THEN 1 END) as em_andamento,
  COUNT(CASE WHEN status = 'pausada' THEN 1 END) as pausadas,
  COUNT(CASE WHEN status = 'concluida' THEN 1 END) as concluidas,
  COUNT(CASE WHEN status = 'cancelada' THEN 1 END) as canceladas,
  COALESCE(SUM(orcamento), 0) as orcamento_total,
  ROUND(AVG(progresso), 0) as progresso_medio
FROM campanhas
GROUP BY cliente_id, ano;

-- View: Campanhas por mês (para timeline)
CREATE OR REPLACE VIEW v_campanhas_timeline AS
SELECT 
  c.id,
  c.cliente_id,
  c.nome,
  c.tipo,
  c.cor,
  c.icone,
  c.status,
  c.progresso,
  c.prioridade,
  c.ano,
  c.mes_inicio,
  c.mes_fim,
  (c.mes_fim - c.mes_inicio + 1) as duracao_meses,
  c.meta_principal,
  cli.nome as cliente_nome
FROM campanhas c
JOIN clientes cli ON c.cliente_id = cli.id
ORDER BY c.ano, c.mes_inicio, c.prioridade DESC;

-- =====================================================
-- TASK 1.8: FUNÇÃO PARA VERIFICAR CONFLITOS
-- =====================================================

CREATE OR REPLACE FUNCTION get_campanhas_do_mes(
  p_cliente_id uuid,
  p_ano int,
  p_mes int
)
RETURNS TABLE (
  id uuid, 
  nome varchar, 
  tipo varchar,
  cor varchar,
  icone varchar,
  status varchar,
  mes_inicio int, 
  mes_fim int
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.id, 
    c.nome, 
    c.tipo,
    c.cor,
    c.icone,
    c.status,
    c.mes_inicio, 
    c.mes_fim
  FROM campanhas c
  WHERE c.cliente_id = p_cliente_id
    AND c.ano = p_ano
    AND p_mes BETWEEN c.mes_inicio AND c.mes_fim
  ORDER BY c.prioridade DESC, c.mes_inicio;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Função para buscar campanhas que conflitam com um período
CREATE OR REPLACE FUNCTION get_campanhas_conflitantes(
  p_cliente_id uuid,
  p_ano int,
  p_mes_inicio int,
  p_mes_fim int,
  p_excluir_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid, 
  nome varchar, 
  mes_inicio int, 
  mes_fim int
) AS $$
BEGIN
  RETURN QUERY
  SELECT c.id, c.nome, c.mes_inicio, c.mes_fim
  FROM campanhas c
  WHERE c.cliente_id = p_cliente_id
    AND c.ano = p_ano
    AND c.id IS DISTINCT FROM p_excluir_id
    AND (
      (p_mes_inicio BETWEEN c.mes_inicio AND c.mes_fim)
      OR (p_mes_fim BETWEEN c.mes_inicio AND c.mes_fim)
      OR (c.mes_inicio BETWEEN p_mes_inicio AND p_mes_fim)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- GRANTS (permissões)
-- =====================================================

-- Grants para as views
GRANT SELECT ON v_campanhas_stats TO authenticated;
GRANT SELECT ON v_planejamento_anual TO authenticated;
GRANT SELECT ON v_campanhas_timeline TO authenticated;

-- Grants para as funções
GRANT EXECUTE ON FUNCTION get_campanhas_do_mes TO authenticated;
GRANT EXECUTE ON FUNCTION get_campanhas_conflitantes TO authenticated;

-- =====================================================
-- FIM DA MIGRATION
-- =====================================================


-- ============================================================
-- SOURCE: supabase/migrations/20260212_planejamento_anual_v3.sql
-- ============================================================

-- =====================================================
-- MIGRATION: Módulo de Planejamento Anual (v3 CORRIGIDA)
-- Data: 12/02/2026
-- CORREÇÃO: Usa tabela "members" com campo "org_id"
-- =====================================================

-- =====================================================
-- TASK 1.1: TABELA campanhas
-- =====================================================

CREATE TABLE IF NOT EXISTS campanhas (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  cliente_id uuid NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
  
  -- Identificação
  nome varchar(255) NOT NULL,
  slug varchar(255),
  descricao text,
  objetivo text,
  acoes_planejadas text,
  
  -- Período
  ano int NOT NULL,
  mes_inicio int NOT NULL CHECK (mes_inicio >= 1 AND mes_inicio <= 12),
  mes_fim int NOT NULL CHECK (mes_fim >= 1 AND mes_fim <= 12),
  data_inicio date,
  data_fim date,
  
  -- Categorização
  tipo varchar(50) DEFAULT 'campanha',
  cor varchar(7) DEFAULT '#3B82F6',
  icone varchar(50),
  prioridade int DEFAULT 2 CHECK (prioridade >= 1 AND prioridade <= 3),
  
  -- Metas e Orçamento
  meta_principal text,
  meta_secundaria text,
  kpi_esperado jsonb,
  orcamento decimal(12,2),
  
  -- Status e Progresso
  status varchar(30) DEFAULT 'planejada',
  progresso int DEFAULT 0 CHECK (progresso >= 0 AND progresso <= 100),
  
  -- Relacionamentos
  responsavel_id uuid REFERENCES auth.users(id),
  
  -- Metadados
  created_by uuid REFERENCES auth.users(id),
  updated_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

COMMENT ON TABLE campanhas IS 'Campanhas e ações planejadas por cliente/ano';

-- =====================================================
-- TASK 1.2: TABELA campanha_conteudos
-- =====================================================

CREATE TABLE IF NOT EXISTS campanha_conteudos (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  campanha_id uuid NOT NULL REFERENCES campanhas(id) ON DELETE CASCADE,
  conteudo_id uuid NOT NULL REFERENCES conteudos(id) ON DELETE CASCADE,
  ordem int DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  
  UNIQUE(campanha_id, conteudo_id)
);

-- =====================================================
-- TASK 1.3: TABELA campanha_historico
-- =====================================================

CREATE TABLE IF NOT EXISTS campanha_historico (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  campanha_id uuid NOT NULL REFERENCES campanhas(id) ON DELETE CASCADE,
  acao varchar(50) NOT NULL,
  campo_alterado varchar(100),
  valor_anterior text,
  valor_novo text,
  user_id uuid REFERENCES auth.users(id),
  user_email varchar(255),
  created_at timestamptz DEFAULT now()
);

-- =====================================================
-- TASK 1.4: ÍNDICES
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_campanhas_org ON campanhas(org_id);
CREATE INDEX IF NOT EXISTS idx_campanhas_cliente ON campanhas(cliente_id);
CREATE INDEX IF NOT EXISTS idx_campanhas_ano ON campanhas(ano);
CREATE INDEX IF NOT EXISTS idx_campanhas_status ON campanhas(status);
CREATE INDEX IF NOT EXISTS idx_campanhas_tipo ON campanhas(tipo);
CREATE INDEX IF NOT EXISTS idx_campanhas_periodo ON campanhas(ano, mes_inicio, mes_fim);
CREATE INDEX IF NOT EXISTS idx_campanhas_cliente_ano ON campanhas(cliente_id, ano);
CREATE INDEX IF NOT EXISTS idx_campanhas_created ON campanhas(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_campanha_conteudos_campanha ON campanha_conteudos(campanha_id);
CREATE INDEX IF NOT EXISTS idx_campanha_conteudos_conteudo ON campanha_conteudos(conteudo_id);
CREATE INDEX IF NOT EXISTS idx_campanha_historico_campanha ON campanha_historico(campanha_id);
CREATE INDEX IF NOT EXISTS idx_campanha_historico_created ON campanha_historico(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_campanhas_nome_gin ON campanhas USING gin(to_tsvector('portuguese', nome));

-- =====================================================
-- TASK 1.5: RLS (Row Level Security)
-- =====================================================

ALTER TABLE campanhas ENABLE ROW LEVEL SECURITY;
ALTER TABLE campanha_conteudos ENABLE ROW LEVEL SECURITY;
ALTER TABLE campanha_historico ENABLE ROW LEVEL SECURITY;

-- Políticas para campanhas (usando tabela "members" com "org_id")
DROP POLICY IF EXISTS "campanhas_select_policy" ON campanhas;
DROP POLICY IF EXISTS "campanhas_select_policy" ON campanhas;
CREATE POLICY "campanhas_select_policy" ON campanhas
  FOR SELECT USING (
    org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_insert_policy" ON campanhas;
DROP POLICY IF EXISTS "campanhas_insert_policy" ON campanhas;
CREATE POLICY "campanhas_insert_policy" ON campanhas
  FOR INSERT WITH CHECK (
    org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_update_policy" ON campanhas;
DROP POLICY IF EXISTS "campanhas_update_policy" ON campanhas;
CREATE POLICY "campanhas_update_policy" ON campanhas
  FOR UPDATE USING (
    org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_delete_policy" ON campanhas;
DROP POLICY IF EXISTS "campanhas_delete_policy" ON campanhas;
CREATE POLICY "campanhas_delete_policy" ON campanhas
  FOR DELETE USING (
    org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
  );

-- Políticas para campanha_conteudos
DROP POLICY IF EXISTS "campanha_conteudos_select_policy" ON campanha_conteudos;
DROP POLICY IF EXISTS "campanha_conteudos_select_policy" ON campanha_conteudos;
CREATE POLICY "campanha_conteudos_select_policy" ON campanha_conteudos
  FOR SELECT USING (
    campanha_id IN (
      SELECT id FROM campanhas WHERE org_id IN (
        SELECT org_id FROM members WHERE user_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS "campanha_conteudos_all_policy" ON campanha_conteudos;
DROP POLICY IF EXISTS "campanha_conteudos_all_policy" ON campanha_conteudos;
CREATE POLICY "campanha_conteudos_all_policy" ON campanha_conteudos
  FOR ALL USING (
    campanha_id IN (
      SELECT id FROM campanhas WHERE org_id IN (
        SELECT org_id FROM members WHERE user_id = auth.uid()
      )
    )
  );

-- Políticas para campanha_historico
DROP POLICY IF EXISTS "campanha_historico_select_policy" ON campanha_historico;
DROP POLICY IF EXISTS "campanha_historico_select_policy" ON campanha_historico;
CREATE POLICY "campanha_historico_select_policy" ON campanha_historico
  FOR SELECT USING (
    campanha_id IN (
      SELECT id FROM campanhas WHERE org_id IN (
        SELECT org_id FROM members WHERE user_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS "campanha_historico_insert_policy" ON campanha_historico;
DROP POLICY IF EXISTS "campanha_historico_insert_policy" ON campanha_historico;
CREATE POLICY "campanha_historico_insert_policy" ON campanha_historico
  FOR INSERT WITH CHECK (
    campanha_id IN (
      SELECT id FROM campanhas WHERE org_id IN (
        SELECT org_id FROM members WHERE user_id = auth.uid()
      )
    )
  );

-- =====================================================
-- TASK 1.6: TRIGGERS
-- =====================================================

CREATE OR REPLACE FUNCTION update_campanhas_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS campanhas_updated_at ON campanhas;
DROP TRIGGER IF EXISTS campanhas_updated_at ON campanhas;
CREATE TRIGGER campanhas_updated_at
  BEFORE UPDATE ON campanhas
  FOR EACH ROW
  EXECUTE FUNCTION update_campanhas_updated_at();

CREATE OR REPLACE FUNCTION generate_campanha_slug()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.slug IS NULL OR NEW.slug = '' THEN
    NEW.slug = lower(
      regexp_replace(
        translate(NEW.nome, 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ', 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'),
        '[^a-zA-Z0-9]+', '-', 'g'
      )
    );
    NEW.slug = regexp_replace(NEW.slug, '-+', '-', 'g');
    NEW.slug = trim(both '-' from NEW.slug);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS campanhas_generate_slug ON campanhas;
DROP TRIGGER IF EXISTS campanhas_generate_slug ON campanhas;
CREATE TRIGGER campanhas_generate_slug
  BEFORE INSERT OR UPDATE OF nome ON campanhas
  FOR EACH ROW
  EXECUTE FUNCTION generate_campanha_slug();

CREATE OR REPLACE FUNCTION log_campanha_changes()
RETURNS TRIGGER AS $$
DECLARE
  v_user_email varchar(255);
BEGIN
  SELECT email INTO v_user_email FROM auth.users WHERE id = auth.uid();
  
  IF TG_OP = 'INSERT' THEN
    INSERT INTO campanha_historico (campanha_id, acao, user_id, user_email)
    VALUES (NEW.id, 'created', auth.uid(), v_user_email);
    
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
      INSERT INTO campanha_historico (campanha_id, acao, campo_alterado, valor_anterior, valor_novo, user_id, user_email)
      VALUES (NEW.id, 'status_changed', 'status', OLD.status, NEW.status, auth.uid(), v_user_email);
    END IF;
    
    IF OLD.nome IS DISTINCT FROM NEW.nome THEN
      INSERT INTO campanha_historico (campanha_id, acao, campo_alterado, valor_anterior, valor_novo, user_id, user_email)
      VALUES (NEW.id, 'updated', 'nome', OLD.nome, NEW.nome, auth.uid(), v_user_email);
    END IF;
    
    IF OLD.mes_inicio IS DISTINCT FROM NEW.mes_inicio OR OLD.mes_fim IS DISTINCT FROM NEW.mes_fim THEN
      INSERT INTO campanha_historico (campanha_id, acao, campo_alterado, valor_anterior, valor_novo, user_id, user_email)
      VALUES (NEW.id, 'updated', 'periodo', OLD.mes_inicio || '-' || OLD.mes_fim, NEW.mes_inicio || '-' || NEW.mes_fim, auth.uid(), v_user_email);
    END IF;
    
    IF OLD.progresso IS DISTINCT FROM NEW.progresso AND 
       (NEW.progresso = 0 OR NEW.progresso = 25 OR NEW.progresso = 50 OR NEW.progresso = 75 OR NEW.progresso = 100) THEN
      INSERT INTO campanha_historico (campanha_id, acao, campo_alterado, valor_anterior, valor_novo, user_id, user_email)
      VALUES (NEW.id, 'updated', 'progresso', OLD.progresso::text, NEW.progresso::text, auth.uid(), v_user_email);
    END IF;
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS campanhas_audit_log ON campanhas;
DROP TRIGGER IF EXISTS campanhas_audit_log ON campanhas;
CREATE TRIGGER campanhas_audit_log
  AFTER INSERT OR UPDATE ON campanhas
  FOR EACH ROW
  EXECUTE FUNCTION log_campanha_changes();

-- =====================================================
-- TASK 1.7: VIEWS
-- =====================================================

CREATE OR REPLACE VIEW v_campanhas_stats AS
SELECT 
  c.*,
  COALESCE(stats.total_conteudos, 0) as total_conteudos,
  COALESCE(stats.conteudos_publicados, 0) as conteudos_publicados,
  CASE 
    WHEN COALESCE(stats.total_conteudos, 0) = 0 THEN 0
    ELSE ROUND(COALESCE(stats.conteudos_publicados, 0)::numeric / stats.total_conteudos * 100, 0)
  END as percentual_publicado,
  cli.nome as cliente_nome,
  cli.slug as cliente_slug
FROM campanhas c
LEFT JOIN clientes cli ON c.cliente_id = cli.id
LEFT JOIN LATERAL (
  SELECT 
    COUNT(cc.id) as total_conteudos,
    COUNT(CASE WHEN cont.status = 'publicado' THEN 1 END) as conteudos_publicados
  FROM campanha_conteudos cc
  LEFT JOIN conteudos cont ON cc.conteudo_id = cont.id
  WHERE cc.campanha_id = c.id
) stats ON true;

CREATE OR REPLACE VIEW v_planejamento_anual AS
SELECT 
  cliente_id,
  ano,
  COUNT(*) as total_campanhas,
  COUNT(CASE WHEN status = 'planejada' THEN 1 END) as planejadas,
  COUNT(CASE WHEN status = 'em_andamento' THEN 1 END) as em_andamento,
  COUNT(CASE WHEN status = 'pausada' THEN 1 END) as pausadas,
  COUNT(CASE WHEN status = 'concluida' THEN 1 END) as concluidas,
  COUNT(CASE WHEN status = 'cancelada' THEN 1 END) as canceladas,
  COALESCE(SUM(orcamento), 0) as orcamento_total,
  ROUND(AVG(progresso), 0) as progresso_medio
FROM campanhas
GROUP BY cliente_id, ano;

CREATE OR REPLACE VIEW v_campanhas_timeline AS
SELECT 
  c.id,
  c.cliente_id,
  c.nome,
  c.tipo,
  c.cor,
  c.icone,
  c.status,
  c.progresso,
  c.prioridade,
  c.ano,
  c.mes_inicio,
  c.mes_fim,
  (c.mes_fim - c.mes_inicio + 1) as duracao_meses,
  c.meta_principal,
  cli.nome as cliente_nome
FROM campanhas c
JOIN clientes cli ON c.cliente_id = cli.id
ORDER BY c.ano, c.mes_inicio, c.prioridade DESC;

-- =====================================================
-- TASK 1.8: FUNÇÕES
-- =====================================================

CREATE OR REPLACE FUNCTION get_campanhas_do_mes(
  p_cliente_id uuid,
  p_ano int,
  p_mes int
)
RETURNS TABLE (
  id uuid, 
  nome varchar, 
  tipo varchar,
  cor varchar,
  icone varchar,
  status varchar,
  mes_inicio int, 
  mes_fim int
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.id, c.nome, c.tipo, c.cor, c.icone, c.status, c.mes_inicio, c.mes_fim
  FROM campanhas c
  WHERE c.cliente_id = p_cliente_id
    AND c.ano = p_ano
    AND p_mes BETWEEN c.mes_inicio AND c.mes_fim
  ORDER BY c.prioridade DESC, c.mes_inicio;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_campanhas_conflitantes(
  p_cliente_id uuid,
  p_ano int,
  p_mes_inicio int,
  p_mes_fim int,
  p_excluir_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid, 
  nome varchar, 
  mes_inicio int, 
  mes_fim int
) AS $$
BEGIN
  RETURN QUERY
  SELECT c.id, c.nome, c.mes_inicio, c.mes_fim
  FROM campanhas c
  WHERE c.cliente_id = p_cliente_id
    AND c.ano = p_ano
    AND c.id IS DISTINCT FROM p_excluir_id
    AND (
      (p_mes_inicio BETWEEN c.mes_inicio AND c.mes_fim)
      OR (p_mes_fim BETWEEN c.mes_inicio AND c.mes_fim)
      OR (c.mes_inicio BETWEEN p_mes_inicio AND p_mes_fim)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- GRANTS
-- =====================================================

GRANT SELECT ON v_campanhas_stats TO authenticated;
GRANT SELECT ON v_planejamento_anual TO authenticated;
GRANT SELECT ON v_campanhas_timeline TO authenticated;
GRANT EXECUTE ON FUNCTION get_campanhas_do_mes TO authenticated;
GRANT EXECUTE ON FUNCTION get_campanhas_conflitantes TO authenticated;

-- =====================================================
-- FIM DA MIGRATION v3
-- =====================================================


-- ============================================================
-- SOURCE: supabase/migrations/20260225_create_acervos.sql
-- ============================================================

-- Migration: Criar sistema de Acervo Digital
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
  tipo_origem VARCHAR(20) DEFAULT 'drive', -- 'drive' ou 'upload'
  drive_folder_id VARCHAR(255), -- ID da pasta do Drive
  drive_folder_url TEXT, -- URL completa (pra facilitar)
  
  -- Config
  visibilidade VARCHAR(20) DEFAULT 'publico', -- 'publico' ou 'privado'
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
  tipo VARCHAR(100), -- mime type: 'image/jpeg', 'application/pdf', etc
  tamanho BIGINT, -- bytes
  
  -- URLs
  url_original TEXT, -- URL do Drive ou Supabase
  url_thumbnail TEXT, -- Preview pequeno
  url_download TEXT, -- Link direto de download
  
  -- Metadata
  drive_file_id VARCHAR(255), -- Se vier do Drive
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
-- RLS Policies
-- ============================================

-- Habilitar RLS
ALTER TABLE acervos ENABLE ROW LEVEL SECURITY;
ALTER TABLE acervo_arquivos ENABLE ROW LEVEL SECURITY;

-- Políticas para acervos
DROP POLICY IF EXISTS "Acervos públicos visíveis para todos" ON acervos;
CREATE POLICY "Acervos públicos visíveis para todos" ON acervos
  FOR SELECT
  USING (visibilidade = 'publico' AND ativo = true);

DROP POLICY IF EXISTS "Membros da org podem ver todos acervos" ON acervos;

CREATE POLICY "Membros da org podem ver todos acervos" ON acervos
  FOR SELECT
  USING (
    org_id IN (
      SELECT org_id FROM organization_members WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Membros da org podem criar acervos" ON acervos;

CREATE POLICY "Membros da org podem criar acervos" ON acervos
  FOR INSERT
  WITH CHECK (
    org_id IN (
      SELECT org_id FROM organization_members WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Membros da org podem atualizar acervos" ON acervos;

CREATE POLICY "Membros da org podem atualizar acervos" ON acervos
  FOR UPDATE
  USING (
    org_id IN (
      SELECT org_id FROM organization_members WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Membros da org podem deletar acervos" ON acervos;

CREATE POLICY "Membros da org podem deletar acervos" ON acervos
  FOR DELETE
  USING (
    org_id IN (
      SELECT org_id FROM organization_members WHERE user_id = auth.uid()
    )
  );

-- Políticas para acervo_arquivos
DROP POLICY IF EXISTS "Arquivos de acervos públicos visíveis" ON acervo_arquivos;
CREATE POLICY "Arquivos de acervos públicos visíveis" ON acervo_arquivos
  FOR SELECT
  USING (
    acervo_id IN (
      SELECT id FROM acervos WHERE visibilidade = 'publico' AND ativo = true
    )
  );

DROP POLICY IF EXISTS "Membros podem ver todos arquivos" ON acervo_arquivos;

CREATE POLICY "Membros podem ver todos arquivos" ON acervo_arquivos
  FOR SELECT
  USING (
    acervo_id IN (
      SELECT a.id FROM acervos a
      JOIN organization_members om ON a.org_id = om.org_id
      WHERE om.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Membros podem gerenciar arquivos" ON acervo_arquivos;

CREATE POLICY "Membros podem gerenciar arquivos" ON acervo_arquivos
  FOR ALL
  USING (
    acervo_id IN (
      SELECT a.id FROM acervos a
      JOIN organization_members om ON a.org_id = om.org_id
      WHERE om.user_id = auth.uid()
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
DROP POLICY IF EXISTS "Acervos públicos visíveis para todos" ON acervos;
CREATE POLICY "Acervos públicos visíveis para todos" ON acervos
  FOR SELECT
  USING (visibilidade = 'publico' AND ativo = true);

DROP POLICY IF EXISTS "Membros da org podem ver todos acervos" ON acervos;

CREATE POLICY "Membros da org podem ver todos acervos" ON acervos
  FOR SELECT
  USING (
    org_id IN (
      SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
    )
  );

DROP POLICY IF EXISTS "Membros da org podem criar acervos" ON acervos;

CREATE POLICY "Membros da org podem criar acervos" ON acervos
  FOR INSERT
  WITH CHECK (
    org_id IN (
      SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
    )
  );

DROP POLICY IF EXISTS "Membros da org podem atualizar acervos" ON acervos;

CREATE POLICY "Membros da org podem atualizar acervos" ON acervos
  FOR UPDATE
  USING (
    org_id IN (
      SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
    )
  );

DROP POLICY IF EXISTS "Membros da org podem deletar acervos" ON acervos;

CREATE POLICY "Membros da org podem deletar acervos" ON acervos
  FOR DELETE
  USING (
    org_id IN (
      SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active'
    )
  );

-- Políticas para acervo_arquivos
DROP POLICY IF EXISTS "Arquivos de acervos públicos visíveis" ON acervo_arquivos;
CREATE POLICY "Arquivos de acervos públicos visíveis" ON acervo_arquivos
  FOR SELECT
  USING (
    acervo_id IN (
      SELECT id FROM acervos WHERE visibilidade = 'publico' AND ativo = true
    )
  );

DROP POLICY IF EXISTS "Membros podem ver todos arquivos" ON acervo_arquivos;

CREATE POLICY "Membros podem ver todos arquivos" ON acervo_arquivos
  FOR SELECT
  USING (
    acervo_id IN (
      SELECT a.id FROM acervos a
      JOIN members m ON a.org_id = m.org_id
      WHERE m.user_id = auth.uid() AND m.status = 'active'
    )
  );

DROP POLICY IF EXISTS "Membros podem gerenciar arquivos" ON acervo_arquivos;

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
DROP POLICY IF EXISTS "Aprovadores visíveis para todos autenticados" ON aprovadores;
CREATE POLICY "Aprovadores visíveis para todos autenticados" ON aprovadores
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Aprovadores editáveis por admins" ON aprovadores;

CREATE POLICY "Aprovadores editáveis por admins" ON aprovadores
  FOR ALL USING (true);

DROP POLICY IF EXISTS "Histórico visível para todos" ON aprovacoes_historico;

CREATE POLICY "Histórico visível para todos" ON aprovacoes_historico
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Histórico inserível" ON aprovacoes_historico;

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
