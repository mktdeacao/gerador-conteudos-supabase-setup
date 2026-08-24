-- BASE Content Studio / Gerador de Conteúdos
-- Schema consolidado para execução no Supabase SQL Editor.



-- ============================================================
-- SOURCE: sql/001_schema.sql
-- ============================================================

-- ============================================
-- BASE Content Studio 2.0 - Schema Completo
-- Executar no Supabase SQL Editor
-- ============================================

-- 1. ORGANIZATIONS (multi-tenant)
CREATE TABLE IF NOT EXISTS organizations (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name varchar(255) NOT NULL,
  slug varchar(100) UNIQUE NOT NULL,
  logo_url text,
  plan varchar(50) DEFAULT 'free',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- 2. MEMBERS (equipe)
CREATE TABLE IF NOT EXISTS members (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  org_id uuid REFERENCES organizations(id) ON DELETE CASCADE NOT NULL,
  role varchar(20) DEFAULT 'designer' CHECK (role IN ('admin', 'gestor', 'designer', 'cliente')),
  display_name varchar(255),
  avatar_url text,
  invited_by uuid,
  status varchar(20) DEFAULT 'active' CHECK (status IN ('active', 'pending', 'inactive')),
  created_at timestamptz DEFAULT now(),
  UNIQUE(user_id, org_id)
);

-- 3. INVITES
CREATE TABLE IF NOT EXISTS invites (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id uuid REFERENCES organizations(id) ON DELETE CASCADE NOT NULL,
  email varchar(255) NOT NULL,
  role varchar(20) DEFAULT 'designer',
  token varchar(64) UNIQUE NOT NULL,
  invited_by uuid REFERENCES auth.users(id),
  expires_at timestamptz DEFAULT (now() + interval '7 days'),
  accepted_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- 4. CLIENTES (empresas com org_id)
CREATE TABLE IF NOT EXISTS clientes (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id uuid REFERENCES organizations(id) ON DELETE CASCADE NOT NULL,
  nome varchar(255) NOT NULL,
  slug varchar(100) NOT NULL,
  cores jsonb DEFAULT '{"primaria": "#6366F1", "secundaria": "#818CF8"}'::jsonb,
  logo_url text,
  contato text,
  notas text,
  created_at timestamptz DEFAULT now(),
  UNIQUE(org_id, slug)
);

-- 5. CONTEUDOS (planejamento)
CREATE TABLE IF NOT EXISTS conteudos (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id uuid REFERENCES organizations(id) ON DELETE CASCADE NOT NULL,
  empresa_id uuid REFERENCES clientes(id) ON DELETE CASCADE NOT NULL,
  mes int NOT NULL,
  ano int NOT NULL,
  data_publicacao date,
  titulo varchar(500),
  tipo varchar(50) DEFAULT 'carrossel',
  categoria varchar(50) DEFAULT 'social',
  badge varchar(255),
  descricao text,
  slides jsonb DEFAULT '[]'::jsonb,
  prompts_imagem jsonb DEFAULT '[]'::jsonb,
  prompts_video jsonb DEFAULT '[]'::jsonb,
  legenda text,
  status varchar(50) DEFAULT 'rascunho',
  ordem int DEFAULT 1,
  midia_urls jsonb DEFAULT '[]'::jsonb,
  canais jsonb DEFAULT '[]'::jsonb,
  assigned_to uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- 6. APROVAÇÕES
CREATE TABLE IF NOT EXISTS aprovacoes_links (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  conteudo_id uuid REFERENCES conteudos(id) ON DELETE CASCADE,
  empresa_id uuid REFERENCES clientes(id) ON DELETE CASCADE,
  token varchar(64) UNIQUE NOT NULL,
  status varchar(20) DEFAULT 'pendente' CHECK (status IN ('pendente', 'aprovado', 'ajuste')),
  comentario_cliente text,
  cliente_nome varchar(255),
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz DEFAULT (now() + interval '30 days'),
  aprovado_em timestamptz
);

-- 7. MESSAGES (chat)
CREATE TABLE IF NOT EXISTS messages (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id uuid REFERENCES organizations(id) ON DELETE CASCADE NOT NULL,
  conteudo_id uuid REFERENCES conteudos(id) ON DELETE CASCADE,
  cliente_id uuid REFERENCES clientes(id) ON DELETE CASCADE,
  channel_type varchar(20) DEFAULT 'geral' CHECK (channel_type IN ('conteudo', 'cliente', 'geral')),
  sender_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  text text NOT NULL,
  attachments jsonb DEFAULT '[]'::jsonb,
  created_at timestamptz DEFAULT now()
);

-- 8. NOTIFICATIONS
CREATE TABLE IF NOT EXISTS notifications (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  org_id uuid REFERENCES organizations(id) ON DELETE CASCADE NOT NULL,
  type varchar(50) NOT NULL,
  title varchar(255) NOT NULL,
  body text,
  read boolean DEFAULT false,
  reference_id uuid,
  reference_type varchar(50),
  created_at timestamptz DEFAULT now()
);

-- 9. WEBHOOK CONFIGS
CREATE TABLE IF NOT EXISTS webhook_configs (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id uuid REFERENCES organizations(id) ON DELETE CASCADE NOT NULL,
  url text NOT NULL,
  events jsonb DEFAULT '[]'::jsonb,
  active boolean DEFAULT true,
  secret varchar(255),
  created_at timestamptz DEFAULT now()
);

-- 10. WEBHOOK EVENTS LOG
CREATE TABLE IF NOT EXISTS webhook_events (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id uuid REFERENCES organizations(id) ON DELETE CASCADE NOT NULL,
  webhook_id uuid REFERENCES webhook_configs(id) ON DELETE CASCADE,
  event_type varchar(100) NOT NULL,
  payload jsonb,
  status varchar(20) DEFAULT 'pending',
  response_code int,
  sent_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- 11. ACTIVITY LOG
CREATE TABLE IF NOT EXISTS activity_log (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id uuid REFERENCES organizations(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action varchar(100) NOT NULL,
  entity_type varchar(50),
  entity_id uuid,
  details jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);

-- ============================================
-- INDEXES
-- ============================================
CREATE INDEX IF NOT EXISTS idx_members_org ON members(org_id);
CREATE INDEX IF NOT EXISTS idx_members_user ON members(user_id);
CREATE INDEX IF NOT EXISTS idx_clientes_org ON clientes(org_id);
CREATE INDEX IF NOT EXISTS idx_conteudos_org ON conteudos(org_id);
CREATE INDEX IF NOT EXISTS idx_conteudos_empresa ON conteudos(empresa_id, mes, ano);
CREATE INDEX IF NOT EXISTS idx_conteudos_status ON conteudos(org_id, status);
CREATE INDEX IF NOT EXISTS idx_conteudos_assigned ON conteudos(assigned_to);
CREATE INDEX IF NOT EXISTS idx_aprovacoes_token ON aprovacoes_links(token);
CREATE INDEX IF NOT EXISTS idx_messages_conteudo ON messages(conteudo_id);
CREATE INDEX IF NOT EXISTS idx_messages_cliente ON messages(cliente_id);
CREATE INDEX IF NOT EXISTS idx_messages_org ON messages(org_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_org ON activity_log(org_id, created_at DESC);

-- ============================================
-- RLS (Row Level Security)
-- ============================================

-- Organizations: members can see their org
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "org_select" ON organizations FOR SELECT USING (
  id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
);
CREATE POLICY "org_update" ON organizations FOR UPDATE USING (
  id IN (SELECT org_id FROM members WHERE user_id = auth.uid() AND role = 'admin')
);

-- Members: see members of your org
ALTER TABLE members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members_select" ON members FOR SELECT USING (
  org_id IN (SELECT org_id FROM members m WHERE m.user_id = auth.uid())
);
CREATE POLICY "members_insert" ON members FOR INSERT WITH CHECK (
  org_id IN (SELECT org_id FROM members m WHERE m.user_id = auth.uid() AND m.role IN ('admin', 'gestor'))
  OR NOT EXISTS (SELECT 1 FROM members m WHERE m.org_id = org_id)
);
CREATE POLICY "members_update" ON members FOR UPDATE USING (
  org_id IN (SELECT org_id FROM members m WHERE m.user_id = auth.uid() AND m.role = 'admin')
  OR user_id = auth.uid()
);

-- Invites
ALTER TABLE invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY "invites_select" ON invites FOR SELECT USING (
  org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
);
CREATE POLICY "invites_insert" ON invites FOR INSERT WITH CHECK (
  org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid() AND role IN ('admin', 'gestor'))
);
CREATE POLICY "invites_public_token" ON invites FOR SELECT USING (true);

-- Clientes: org members
ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "clientes_all" ON clientes FOR ALL USING (
  org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
);

-- Conteudos: org members
ALTER TABLE conteudos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "conteudos_all" ON conteudos FOR ALL USING (
  org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
);

-- Aprovações: public read by token, org members full
ALTER TABLE aprovacoes_links ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aprovacoes_public_read" ON aprovacoes_links FOR SELECT USING (true);
CREATE POLICY "aprovacoes_org_write" ON aprovacoes_links FOR INSERT WITH CHECK (
  empresa_id IN (SELECT id FROM clientes WHERE org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid()))
);
CREATE POLICY "aprovacoes_update" ON aprovacoes_links FOR UPDATE USING (true);

-- Messages: org members
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "messages_all" ON messages FOR ALL USING (
  org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
);

-- Notifications: own only
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notifications_own" ON notifications FOR ALL USING (user_id = auth.uid());

-- Webhook configs: admin only
ALTER TABLE webhook_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "webhooks_admin" ON webhook_configs FOR ALL USING (
  org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid() AND role = 'admin')
);

-- Webhook events: admin read
ALTER TABLE webhook_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "webhook_events_read" ON webhook_events FOR SELECT USING (
  org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid() AND role = 'admin')
);

-- Activity log: org members read
ALTER TABLE activity_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "activity_read" ON activity_log FOR SELECT USING (
  org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
);
CREATE POLICY "activity_insert" ON activity_log FOR INSERT WITH CHECK (
  org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
);

-- ============================================
-- REALTIME (para chat e notificações)
-- ============================================
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE conteudos;

-- ============================================
-- FUNCTIONS
-- ============================================

-- Auto-create org + member on first signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger AS $$
DECLARE
  new_org_id uuid;
  user_name text;
BEGIN
  user_name := COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1));
  
  -- Create default organization
  INSERT INTO organizations (name, slug)
  VALUES (user_name || '''s Workspace', lower(replace(user_name, ' ', '-')) || '-' || substr(NEW.id::text, 1, 8))
  RETURNING id INTO new_org_id;
  
  -- Add as admin member
  INSERT INTO members (user_id, org_id, role, display_name, status)
  VALUES (NEW.id, new_org_id, 'admin', user_name, 'active');
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Log activity function
CREATE OR REPLACE FUNCTION log_activity(
  p_org_id uuid,
  p_user_id uuid,
  p_action text,
  p_entity_type text DEFAULT NULL,
  p_entity_id uuid DEFAULT NULL,
  p_details jsonb DEFAULT '{}'
)
RETURNS void AS $$
BEGIN
  INSERT INTO activity_log (org_id, user_id, action, entity_type, entity_id, details)
  VALUES (p_org_id, p_user_id, p_action, p_entity_type, p_entity_id, p_details);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create notification function
CREATE OR REPLACE FUNCTION create_notification(
  p_user_id uuid,
  p_org_id uuid,
  p_type text,
  p_title text,
  p_body text DEFAULT NULL,
  p_reference_id uuid DEFAULT NULL,
  p_reference_type text DEFAULT NULL
)
RETURNS void AS $$
BEGIN
  INSERT INTO notifications (user_id, org_id, type, title, body, reference_id, reference_type)
  VALUES (p_user_id, p_org_id, p_type, p_title, p_body, p_reference_id, p_reference_type);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- SOURCE: sql/002_fix_and_storage.sql
-- ============================================================

-- ============================================
-- BASE Content Studio v2 - Fixes and Storage
-- ============================================

-- 1. TABELA SOLICITACOES
CREATE TABLE IF NOT EXISTS solicitacoes (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id uuid REFERENCES organizations(id) ON DELETE CASCADE NOT NULL,
  cliente_id uuid REFERENCES clientes(id) ON DELETE CASCADE NOT NULL,
  titulo varchar(500) NOT NULL,
  descricao text,
  referencias jsonb DEFAULT '[]',
  arquivos_ref jsonb DEFAULT '[]',
  prioridade varchar(20) DEFAULT 'normal' CHECK (prioridade IN ('baixa', 'normal', 'alta', 'urgente')),
  prazo_desejado date,
  status varchar(30) DEFAULT 'nova' CHECK (status IN ('nova', 'em_analise', 'aprovada', 'em_producao', 'entregue', 'cancelada')),
  respondido_por uuid REFERENCES auth.users(id),
  resposta text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Indexes para solicitacoes
CREATE INDEX IF NOT EXISTS idx_solicitacoes_org ON solicitacoes(org_id);
CREATE INDEX IF NOT EXISTS idx_solicitacoes_cliente ON solicitacoes(cliente_id);
CREATE INDEX IF NOT EXISTS idx_solicitacoes_status ON solicitacoes(org_id, status);

-- RLS para solicitacoes
ALTER TABLE solicitacoes ENABLE ROW LEVEL SECURITY;

-- Membros da org podem ver todas as solicitações
CREATE POLICY "solicitacoes_org_select" ON solicitacoes FOR SELECT USING (
  org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
);

-- Membros podem criar solicitações
CREATE POLICY "solicitacoes_org_insert" ON solicitacoes FOR INSERT WITH CHECK (
  org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
);

-- Membros podem atualizar solicitações
CREATE POLICY "solicitacoes_org_update" ON solicitacoes FOR UPDATE USING (
  org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
);

-- Membros podem deletar solicitações (admin/gestor)
CREATE POLICY "solicitacoes_org_delete" ON solicitacoes FOR DELETE USING (
  org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid() AND role IN ('admin', 'gestor'))
);

-- 2. STORAGE BUCKET para mídia
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'media',
  'media',
  true,
  52428800, -- 50MB
  ARRAY['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'video/mp4', 'video/webm', 'video/quicktime', 'application/pdf']
)
ON CONFLICT (id) DO NOTHING;

-- Storage policy - public read
CREATE POLICY "Public read access" ON storage.objects FOR SELECT USING (bucket_id = 'media');

-- Storage policy - authenticated users can upload
CREATE POLICY "Authenticated users can upload" ON storage.objects 
FOR INSERT WITH CHECK (bucket_id = 'media' AND auth.role() = 'authenticated');

-- Storage policy - users can update their org's files
CREATE POLICY "Users can update org files" ON storage.objects 
FOR UPDATE USING (
  bucket_id = 'media' AND 
  auth.uid()::text IN (
    SELECT user_id::text FROM members 
    WHERE org_id::text = (storage.foldername(name))[1]
  )
);

-- Storage policy - users can delete their org's files
CREATE POLICY "Users can delete org files" ON storage.objects 
FOR DELETE USING (
  bucket_id = 'media' AND 
  auth.uid()::text IN (
    SELECT user_id::text FROM members 
    WHERE org_id::text = (storage.foldername(name))[1]
  )
);

-- 3. LIMPAR ORGANIZAÇÕES DUPLICADAS
-- Identificar e limpar duplicatas para gabriel.kend@gmail.com
DO $$
DECLARE
    user_uuid uuid;
    base_org_id uuid;
    duplicate_org_ids uuid[];
    org_record record;
BEGIN
    -- Buscar o UUID do usuário gabriel.kend@gmail.com
    SELECT id INTO user_uuid 
    FROM auth.users 
    WHERE email = 'gabriel.kend@gmail.com';
    
    IF user_uuid IS NULL THEN
        RAISE NOTICE 'Usuário gabriel.kend@gmail.com não encontrado';
        RETURN;
    END IF;
    
    -- Buscar a org "Agência BASE" (manter esta)
    SELECT org_id INTO base_org_id 
    FROM members m
    JOIN organizations o ON m.org_id = o.id
    WHERE m.user_id = user_uuid 
    AND (o.name ILIKE '%agência base%' OR o.name ILIKE '%agencia base%' OR o.slug ILIKE '%agencia-base%')
    LIMIT 1;
    
    -- Se não encontrou a Agência BASE, pegar a primeira org do usuário
    IF base_org_id IS NULL THEN
        SELECT org_id INTO base_org_id 
        FROM members 
        WHERE user_id = user_uuid
        LIMIT 1;
        
        -- Renomear para Agência BASE
        UPDATE organizations 
        SET name = 'Agência BASE', 
            slug = 'agencia-base',
            updated_at = now()
        WHERE id = base_org_id;
    END IF;
    
    -- Buscar todas as outras orgs do usuário (duplicatas)
    SELECT ARRAY(
        SELECT m.org_id 
        FROM members m
        WHERE m.user_id = user_uuid 
        AND m.org_id != base_org_id
    ) INTO duplicate_org_ids;
    
    -- Mover dados das orgs duplicatas para a org base
    IF array_length(duplicate_org_ids, 1) > 0 THEN
        RAISE NOTICE 'Movendo dados de % organizações duplicadas para org base %', array_length(duplicate_org_ids, 1), base_org_id;
        
        -- Mover clientes
        UPDATE clientes SET org_id = base_org_id 
        WHERE org_id = ANY(duplicate_org_ids);
        
        -- Mover conteúdos
        UPDATE conteudos SET org_id = base_org_id 
        WHERE org_id = ANY(duplicate_org_ids);
        
        -- Mover mensagens
        UPDATE messages SET org_id = base_org_id 
        WHERE org_id = ANY(duplicate_org_ids);
        
        -- Mover notificações
        UPDATE notifications SET org_id = base_org_id 
        WHERE org_id = ANY(duplicate_org_ids);
        
        -- Mover activity_log
        UPDATE activity_log SET org_id = base_org_id 
        WHERE org_id = ANY(duplicate_org_ids);
        
        -- Mover webhook_configs
        UPDATE webhook_configs SET org_id = base_org_id 
        WHERE org_id = ANY(duplicate_org_ids);
        
        -- Mover webhook_events
        UPDATE webhook_events SET org_id = base_org_id 
        WHERE org_id = ANY(duplicate_org_ids);
        
        -- Remover memberships das orgs duplicadas
        DELETE FROM members WHERE org_id = ANY(duplicate_org_ids);
        
        -- Remover orgs duplicadas
        DELETE FROM organizations WHERE id = ANY(duplicate_org_ids);
        
        RAISE NOTICE 'Limpeza concluída. Org base: %', base_org_id;
    ELSE
        RAISE NOTICE 'Nenhuma duplicata encontrada para o usuário';
    END IF;
END $$;

-- 4. ATUALIZAR CAMPOS DE STATUS DOS CONTEÚDOS
ALTER TABLE conteudos 
ALTER COLUMN status TYPE varchar(50),
DROP CONSTRAINT IF EXISTS conteudos_status_check;

ALTER TABLE conteudos 
ADD CONSTRAINT conteudos_status_check 
CHECK (status IN ('rascunho', 'conteudo', 'design', 'aprovacao_cliente', 'ajustes', 'aprovado_agendado', 'concluido'));

-- 5. FUNÇÃO PARA ATUALIZAR updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger para solicitacoes
CREATE TRIGGER update_solicitacoes_updated_at 
    BEFORE UPDATE ON solicitacoes
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- 6. ADICIONAR SOLICITACOES AO REALTIME
ALTER PUBLICATION supabase_realtime ADD TABLE solicitacoes;

-- 7. FUNÇÃO PARA GERAR TOKEN DE APROVAÇÃO
CREATE OR REPLACE FUNCTION generate_approval_token()
RETURNS text AS $$
BEGIN
  RETURN encode(digest(gen_random_uuid()::text || extract(epoch from now())::text, 'sha256'), 'hex');
END;
$$ LANGUAGE plpgsql;

-- Log de conclusão
DO $$ 
BEGIN 
    RAISE NOTICE 'Migration 002_fix_and_storage.sql executada com sucesso em %', now();
END $$;

-- ============================================================
-- SOURCE: sql/003_fix_rls.sql
-- ============================================================

-- ============================================
-- FIX RLS: Resolve infinite recursion on members table
-- Execute this in the Supabase SQL Editor
-- ============================================

-- 1. SECURITY DEFINER functions (break the recursion cycle)
CREATE OR REPLACE FUNCTION get_user_org_ids()
RETURNS SETOF uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT org_id FROM members WHERE user_id = auth.uid() AND status = 'active';
$$;

CREATE OR REPLACE FUNCTION is_org_admin(check_org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS(
    SELECT 1 FROM members 
    WHERE user_id = auth.uid() 
    AND org_id = check_org_id 
    AND role = 'admin' 
    AND status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION is_org_manager(check_org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS(
    SELECT 1 FROM members 
    WHERE user_id = auth.uid() 
    AND org_id = check_org_id 
    AND role IN ('admin', 'gestor') 
    AND status = 'active'
  );
$$;

-- 2. Drop ALL old policies
DROP POLICY IF EXISTS "org_select" ON organizations;
DROP POLICY IF EXISTS "org_update" ON organizations;
DROP POLICY IF EXISTS "org_insert" ON organizations;
DROP POLICY IF EXISTS "members_select" ON members;
DROP POLICY IF EXISTS "members_insert" ON members;
DROP POLICY IF EXISTS "members_update" ON members;
DROP POLICY IF EXISTS "clientes_all" ON clientes;
DROP POLICY IF EXISTS "clientes_select" ON clientes;
DROP POLICY IF EXISTS "clientes_insert" ON clientes;
DROP POLICY IF EXISTS "clientes_update" ON clientes;
DROP POLICY IF EXISTS "clientes_delete" ON clientes;
DROP POLICY IF EXISTS "conteudos_all" ON conteudos;
DROP POLICY IF EXISTS "conteudos_select" ON conteudos;
DROP POLICY IF EXISTS "conteudos_insert" ON conteudos;
DROP POLICY IF EXISTS "conteudos_update" ON conteudos;
DROP POLICY IF EXISTS "conteudos_delete" ON conteudos;
DROP POLICY IF EXISTS "messages_all" ON messages;
DROP POLICY IF EXISTS "messages_select" ON messages;
DROP POLICY IF EXISTS "messages_insert" ON messages;
DROP POLICY IF EXISTS "messages_update" ON messages;
DROP POLICY IF EXISTS "messages_delete" ON messages;
DROP POLICY IF EXISTS "notifications_own" ON notifications;
DROP POLICY IF EXISTS "webhooks_admin" ON webhook_configs;
DROP POLICY IF EXISTS "webhook_events_read" ON webhook_events;
DROP POLICY IF EXISTS "activity_read" ON activity_log;
DROP POLICY IF EXISTS "activity_insert" ON activity_log;
DROP POLICY IF EXISTS "invites_select" ON invites;
DROP POLICY IF EXISTS "invites_insert" ON invites;
DROP POLICY IF EXISTS "invites_public_token" ON invites;
DROP POLICY IF EXISTS "aprovacoes_public_read" ON aprovacoes_links;
DROP POLICY IF EXISTS "aprovacoes_org_write" ON aprovacoes_links;
DROP POLICY IF EXISTS "aprovacoes_update" ON aprovacoes_links;
DROP POLICY IF EXISTS "solicitacoes_org_select" ON solicitacoes;
DROP POLICY IF EXISTS "solicitacoes_org_insert" ON solicitacoes;
DROP POLICY IF EXISTS "solicitacoes_org_update" ON solicitacoes;
DROP POLICY IF EXISTS "solicitacoes_org_delete" ON solicitacoes;
DROP POLICY IF EXISTS "solicitacoes_select" ON solicitacoes;
DROP POLICY IF EXISTS "solicitacoes_insert" ON solicitacoes;
DROP POLICY IF EXISTS "solicitacoes_update" ON solicitacoes;
DROP POLICY IF EXISTS "solicitacoes_delete" ON solicitacoes;

-- 3. New policies using SECURITY DEFINER functions

-- MEMBERS
CREATE POLICY "members_select" ON members FOR SELECT USING (
  org_id IN (SELECT get_user_org_ids())
);
CREATE POLICY "members_insert" ON members FOR INSERT WITH CHECK (
  is_org_manager(org_id) OR NOT EXISTS (SELECT 1 FROM members m2 WHERE m2.org_id = org_id)
);
CREATE POLICY "members_update" ON members FOR UPDATE USING (
  is_org_admin(org_id) OR user_id = auth.uid()
);

-- ORGANIZATIONS
CREATE POLICY "org_select" ON organizations FOR SELECT USING (
  id IN (SELECT get_user_org_ids())
);
CREATE POLICY "org_update" ON organizations FOR UPDATE USING (
  is_org_admin(id)
);
CREATE POLICY "org_insert" ON organizations FOR INSERT WITH CHECK (true);

-- CLIENTES
CREATE POLICY "clientes_select" ON clientes FOR SELECT USING (org_id IN (SELECT get_user_org_ids()));
CREATE POLICY "clientes_insert" ON clientes FOR INSERT WITH CHECK (org_id IN (SELECT get_user_org_ids()));
CREATE POLICY "clientes_update" ON clientes FOR UPDATE USING (org_id IN (SELECT get_user_org_ids()));
CREATE POLICY "clientes_delete" ON clientes FOR DELETE USING (org_id IN (SELECT get_user_org_ids()));

-- CONTEUDOS
CREATE POLICY "conteudos_select" ON conteudos FOR SELECT USING (org_id IN (SELECT get_user_org_ids()));
CREATE POLICY "conteudos_insert" ON conteudos FOR INSERT WITH CHECK (org_id IN (SELECT get_user_org_ids()));
CREATE POLICY "conteudos_update" ON conteudos FOR UPDATE USING (org_id IN (SELECT get_user_org_ids()));
CREATE POLICY "conteudos_delete" ON conteudos FOR DELETE USING (org_id IN (SELECT get_user_org_ids()));

-- MESSAGES
CREATE POLICY "messages_select" ON messages FOR SELECT USING (org_id IN (SELECT get_user_org_ids()));
CREATE POLICY "messages_insert" ON messages FOR INSERT WITH CHECK (org_id IN (SELECT get_user_org_ids()));
CREATE POLICY "messages_update" ON messages FOR UPDATE USING (org_id IN (SELECT get_user_org_ids()));
CREATE POLICY "messages_delete" ON messages FOR DELETE USING (org_id IN (SELECT get_user_org_ids()));

-- NOTIFICATIONS
CREATE POLICY "notifications_own" ON notifications FOR ALL USING (user_id = auth.uid());

-- WEBHOOK CONFIGS
CREATE POLICY "webhooks_admin" ON webhook_configs FOR ALL USING (is_org_admin(org_id));

-- WEBHOOK EVENTS
CREATE POLICY "webhook_events_read" ON webhook_events FOR SELECT USING (is_org_admin(org_id));

-- ACTIVITY LOG
CREATE POLICY "activity_read" ON activity_log FOR SELECT USING (org_id IN (SELECT get_user_org_ids()));
CREATE POLICY "activity_insert" ON activity_log FOR INSERT WITH CHECK (org_id IN (SELECT get_user_org_ids()));

-- INVITES
CREATE POLICY "invites_public_token" ON invites FOR SELECT USING (true);
CREATE POLICY "invites_insert" ON invites FOR INSERT WITH CHECK (is_org_manager(org_id));

-- APROVACOES
CREATE POLICY "aprovacoes_public_read" ON aprovacoes_links FOR SELECT USING (true);
CREATE POLICY "aprovacoes_org_write" ON aprovacoes_links FOR INSERT WITH CHECK (true);
CREATE POLICY "aprovacoes_update" ON aprovacoes_links FOR UPDATE USING (true);

-- SOLICITACOES
CREATE POLICY "solicitacoes_select" ON solicitacoes FOR SELECT USING (org_id IN (SELECT get_user_org_ids()));
CREATE POLICY "solicitacoes_insert" ON solicitacoes FOR INSERT WITH CHECK (org_id IN (SELECT get_user_org_ids()));
CREATE POLICY "solicitacoes_update" ON solicitacoes FOR UPDATE USING (org_id IN (SELECT get_user_org_ids()));
CREATE POLICY "solicitacoes_delete" ON solicitacoes FOR DELETE USING (is_org_manager(org_id));


-- ============================================================
-- SOURCE: sql/004_settings_personalization.sql
-- ============================================================

-- ============================================
-- BASE Content Studio v2 - Sprint 3
-- Settings & Personalization
-- ============================================

-- 1. Add brand/accent colors to organizations
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS brand_color text DEFAULT '#6366F1';
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS accent_color text DEFAULT '#3B82F6';
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS favicon_url text;

-- 2. Add notification preferences to members (JSON field)
ALTER TABLE members ADD COLUMN IF NOT EXISTS notification_prefs jsonb DEFAULT '{"new_requests":true,"pending_approvals":true,"chat_messages":true,"upcoming_deadlines":true}'::jsonb;

-- 3. Ensure media bucket exists with proper policies for uploads
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('media', 'media', true, 5242880, '{image/png,image/jpeg,image/gif,image/webp,image/svg+xml,video/mp4,video/webm,application/pdf}')
ON CONFLICT (id) DO NOTHING;

-- Storage policy: service role can do everything (already handled by default)
-- Public read access
DO $$ BEGIN
  CREATE POLICY "Public read media" ON storage.objects FOR SELECT USING (bucket_id = 'media');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Service role upload (handled by default service_role bypass)


-- ============================================================
-- SOURCE: sql/005_fix_trigger_invites.sql
-- ============================================================

-- ============================================
-- FIX: handle_new_user trigger com suporte a convites
-- Roda no Supabase Dashboard > SQL Editor
-- ============================================

-- 1. Criar tabela member_clients (se não existe)
CREATE TABLE IF NOT EXISTS member_clients (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  member_id uuid NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  cliente_id uuid NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
  org_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE(member_id, cliente_id)
);
ALTER TABLE member_clients ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN
  CREATE POLICY "service_role_all" ON member_clients FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 2. Adicionar coluna solicitacao_id em conteudos (link solicitação → conteúdo)
ALTER TABLE conteudos ADD COLUMN IF NOT EXISTS solicitacao_id uuid REFERENCES solicitacoes(id) ON DELETE SET NULL;

-- 3. Atualizar trigger para suportar convites
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger AS $$
DECLARE
  new_org_id uuid;
  user_name text;
  existing_invite record;
BEGIN
  user_name := COALESCE(
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'display_name',
    split_part(NEW.email, '@', 1)
  );
  
  -- Check if there's a pending invite for this email
  SELECT * INTO existing_invite FROM invites 
  WHERE email = NEW.email 
    AND accepted_at IS NULL 
  ORDER BY created_at DESC 
  LIMIT 1;
  
  IF existing_invite IS NOT NULL THEN
    -- User was invited: add to EXISTING org (don't create new one)
    INSERT INTO members (user_id, org_id, role, display_name, status)
    VALUES (NEW.id, existing_invite.org_id, existing_invite.role, user_name, 'active');
    
    -- Mark invite as accepted
    UPDATE invites SET accepted_at = NOW() WHERE id = existing_invite.id;
  ELSE
    -- New standalone user: create default org
    INSERT INTO organizations (name, slug)
    VALUES (
      user_name || '''s Workspace', 
      lower(replace(user_name, ' ', '-')) || '-' || substr(NEW.id::text, 1, 8)
    )
    RETURNING id INTO new_org_id;
    
    INSERT INTO members (user_id, org_id, role, display_name, status)
    VALUES (NEW.id, new_org_id, 'admin', user_name, 'active');
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Recriar trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();


-- ============================================================
-- SOURCE: sql/006_social_accounts.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS social_accounts (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id uuid REFERENCES organizations(id) ON DELETE CASCADE NOT NULL,
  cliente_id uuid REFERENCES clientes(id) ON DELETE CASCADE NOT NULL,
  platform varchar(50) NOT NULL,
  profile_id varchar(255),
  profile_name varchar(255),
  profile_avatar varchar(500),
  upload_post_user_id varchar(255),
  status varchar(20) DEFAULT 'active',
  connected_at timestamptz DEFAULT now(),
  UNIQUE(cliente_id, platform, profile_id)
);

ALTER TABLE social_accounts ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "service_role_all" ON social_accounts FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- SOURCE: sql/007_scheduled_posts.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS scheduled_posts (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id uuid REFERENCES organizations(id) ON DELETE CASCADE NOT NULL,
  conteudo_id uuid REFERENCES conteudos(id) ON DELETE SET NULL,
  cliente_id uuid REFERENCES clientes(id) ON DELETE CASCADE NOT NULL,
  platforms jsonb NOT NULL DEFAULT '[]',
  caption text,
  media_urls text[] DEFAULT '{}',
  hashtags text[] DEFAULT '{}',
  scheduled_at timestamptz NOT NULL,
  published_at timestamptz,
  status varchar(30) DEFAULT 'scheduled',
  upload_post_id varchar(255),
  upload_post_response jsonb,
  published_urls jsonb DEFAULT '[]',
  error_message text,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE scheduled_posts ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "service_role_all" ON scheduled_posts FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- SOURCE: sql/008_analytics.sql
-- ============================================================

-- Sprint 10: Analytics snapshots table
CREATE TABLE IF NOT EXISTS analytics_snapshots (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id uuid REFERENCES organizations(id) ON DELETE CASCADE NOT NULL,
  cliente_id uuid REFERENCES clientes(id) ON DELETE CASCADE NOT NULL,
  platform varchar(50) NOT NULL,
  snapshot_date date NOT NULL DEFAULT CURRENT_DATE,
  followers integer DEFAULT 0,
  impressions integer DEFAULT 0,
  reach integer DEFAULT 0,
  profile_views integer DEFAULT 0,
  likes integer DEFAULT 0,
  comments integer DEFAULT 0,
  shares integer DEFAULT 0,
  engagement_rate decimal(5,2) DEFAULT 0,
  raw_data jsonb,
  created_at timestamptz DEFAULT now(),
  UNIQUE(cliente_id, platform, snapshot_date)
);

ALTER TABLE analytics_snapshots ENABLE ROW LEVEL SECURITY;

DO $policy$ BEGIN
  CREATE POLICY "service_role_all" ON analytics_snapshots FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $policy$;


-- ============================================================
-- SOURCE: sql/009_client_assets.sql
-- ============================================================

-- Sprint 11: Repositório de Arquivos por Cliente
-- Table for client file assets with folder organization

CREATE TABLE IF NOT EXISTS client_assets (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id uuid REFERENCES organizations(id) ON DELETE CASCADE NOT NULL,
  cliente_id uuid REFERENCES clientes(id) ON DELETE CASCADE NOT NULL,
  folder varchar(255) DEFAULT '/',
  filename varchar(500) NOT NULL,
  file_url text NOT NULL,
  file_type varchar(100),
  file_size bigint,
  thumbnail_url text,
  tags text[] DEFAULT '{}',
  description text,
  uploaded_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE client_assets ENABLE ROW LEVEL SECURITY;

DO $policy$ BEGIN
  CREATE POLICY "service_role_all" ON client_assets FOR ALL USING (true) WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $policy$;

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_client_assets_cliente ON client_assets(cliente_id, folder);
CREATE INDEX IF NOT EXISTS idx_client_assets_org ON client_assets(org_id);


-- ============================================================
-- SOURCE: sql/009_invite_client_ids.sql
-- ============================================================

-- ============================================
-- FIX: Adiciona client_ids na tabela invites
-- Substitui o uso incorreto de member_clients com invite.id como FK placeholder
-- Roda no Supabase Dashboard > SQL Editor
-- ============================================

ALTER TABLE invites ADD COLUMN IF NOT EXISTS client_ids uuid[] DEFAULT '{}';


-- ============================================================
-- SOURCE: sql/010_members_is_personal.sql
-- ============================================================

-- ============================================
-- FIX: Adiciona is_personal nos members
-- Permite priorizar orgs compartilhadas sobre orgs pessoais
-- Roda no Supabase Dashboard > SQL Editor
-- ============================================

-- 1. Adiciona coluna
ALTER TABLE members ADD COLUMN IF NOT EXISTS is_personal boolean NOT NULL DEFAULT false;

-- 2. Marca orgs com apenas 1 membro ativo como pessoais (auto-criadas pelo trigger)
UPDATE members SET is_personal = true
WHERE org_id IN (
  SELECT org_id FROM members
  WHERE status = 'active'
  GROUP BY org_id
  HAVING COUNT(*) = 1
);

-- 3. Atualiza o trigger para marcar corretamente
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger AS $$
DECLARE
  new_org_id uuid;
  user_name text;
  existing_invite record;
BEGIN
  user_name := COALESCE(
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'display_name',
    split_part(NEW.email, '@', 1)
  );

  -- Check if there's a pending invite for this email
  SELECT * INTO existing_invite FROM invites
  WHERE email = NEW.email
    AND accepted_at IS NULL
  ORDER BY created_at DESC
  LIMIT 1;

  IF existing_invite IS NOT NULL THEN
    -- User was invited: add to EXISTING org (not personal)
    INSERT INTO members (user_id, org_id, role, display_name, status, is_personal)
    VALUES (NEW.id, existing_invite.org_id, existing_invite.role, user_name, 'active', false);

    UPDATE invites SET accepted_at = NOW() WHERE id = existing_invite.id;
  ELSE
    -- New standalone user: create personal org
    INSERT INTO organizations (name, slug)
    VALUES (
      user_name || '''s Workspace',
      lower(replace(user_name, ' ', '-')) || '-' || substr(NEW.id::text, 1, 8)
    )
    RETURNING id INTO new_org_id;

    INSERT INTO members (user_id, org_id, role, display_name, status, is_personal)
    VALUES (NEW.id, new_org_id, 'admin', user_name, 'active', true);
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- SOURCE: sql/010_brand_book.sql
-- ============================================================

-- Sprint 12: Brand Book por Cliente
-- Adiciona campos de brand book na tabela clientes

ALTER TABLE clientes ADD COLUMN IF NOT EXISTS brand_guidelines jsonb DEFAULT '{}';
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS color_palette jsonb DEFAULT '[]';
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS fonts jsonb DEFAULT '{}';
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS personas jsonb DEFAULT '[]';
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS bio text DEFAULT '';
ALTER TABLE clientes ADD COLUMN IF NOT EXISTS social_links jsonb DEFAULT '{}';


-- ============================================================
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
CREATE POLICY "Members can view org tasks" ON tasks
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM members 
      WHERE members.org_id = tasks.org_id 
      AND members.user_id = auth.uid()
    )
  );

-- Política: membros podem criar tarefas
CREATE POLICY "Members can create tasks" ON tasks
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM members 
      WHERE members.org_id = tasks.org_id 
      AND members.user_id = auth.uid()
    )
  );

-- Política: membros podem atualizar tarefas (atribuídas a eles ou se tiverem permissão full)
CREATE POLICY "Members can update tasks" ON tasks
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM members 
      WHERE members.org_id = tasks.org_id 
      AND members.user_id = auth.uid()
    )
  );

-- Política: apenas admin/gestor podem deletar tarefas
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
CREATE POLICY "Members can view task comments" ON task_comments
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM members 
      WHERE members.org_id = task_comments.org_id 
      AND members.user_id = auth.uid()
    )
  );

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
CREATE POLICY "campanha_notif_select" ON campanha_notificacoes
  FOR SELECT USING (
    org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
  );

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
CREATE POLICY "campanhas_select_policy" ON campanhas
  FOR SELECT USING (
    org_id IN (SELECT org_id FROM org_members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_insert_policy" ON campanhas;
CREATE POLICY "campanhas_insert_policy" ON campanhas
  FOR INSERT WITH CHECK (
    org_id IN (SELECT org_id FROM org_members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_update_policy" ON campanhas;
CREATE POLICY "campanhas_update_policy" ON campanhas
  FOR UPDATE USING (
    org_id IN (SELECT org_id FROM org_members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_delete_policy" ON campanhas;
CREATE POLICY "campanhas_delete_policy" ON campanhas
  FOR DELETE USING (
    org_id IN (SELECT org_id FROM org_members WHERE user_id = auth.uid())
  );

-- Políticas para campanha_conteudos
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
CREATE POLICY "campanha_historico_select_policy" ON campanha_historico
  FOR SELECT USING (
    campanha_id IN (
      SELECT id FROM campanhas WHERE org_id IN (
        SELECT org_id FROM org_members WHERE user_id = auth.uid()
      )
    )
  );

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
CREATE POLICY "campanhas_select_policy" ON campanhas
  FOR SELECT USING (
    organization_id IN (SELECT organization_id FROM organization_members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_insert_policy" ON campanhas;
CREATE POLICY "campanhas_insert_policy" ON campanhas
  FOR INSERT WITH CHECK (
    organization_id IN (SELECT organization_id FROM organization_members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_update_policy" ON campanhas;
CREATE POLICY "campanhas_update_policy" ON campanhas
  FOR UPDATE USING (
    organization_id IN (SELECT organization_id FROM organization_members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_delete_policy" ON campanhas;
CREATE POLICY "campanhas_delete_policy" ON campanhas
  FOR DELETE USING (
    organization_id IN (SELECT organization_id FROM organization_members WHERE user_id = auth.uid())
  );

-- Políticas para campanha_conteudos
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
CREATE POLICY "campanha_historico_select_policy" ON campanha_historico
  FOR SELECT USING (
    campanha_id IN (
      SELECT id FROM campanhas WHERE organization_id IN (
        SELECT organization_id FROM organization_members WHERE user_id = auth.uid()
      )
    )
  );

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
CREATE POLICY "campanhas_select_policy" ON campanhas
  FOR SELECT USING (
    org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_insert_policy" ON campanhas;
CREATE POLICY "campanhas_insert_policy" ON campanhas
  FOR INSERT WITH CHECK (
    org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_update_policy" ON campanhas;
CREATE POLICY "campanhas_update_policy" ON campanhas
  FOR UPDATE USING (
    org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
  );

DROP POLICY IF EXISTS "campanhas_delete_policy" ON campanhas;
CREATE POLICY "campanhas_delete_policy" ON campanhas
  FOR DELETE USING (
    org_id IN (SELECT org_id FROM members WHERE user_id = auth.uid())
  );

-- Políticas para campanha_conteudos
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
CREATE POLICY "campanha_historico_select_policy" ON campanha_historico
  FOR SELECT USING (
    campanha_id IN (
      SELECT id FROM campanhas WHERE org_id IN (
        SELECT org_id FROM members WHERE user_id = auth.uid()
      )
    )
  );

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
CREATE POLICY "Acervos públicos visíveis para todos" ON acervos
  FOR SELECT
  USING (visibilidade = 'publico' AND ativo = true);

CREATE POLICY "Membros da org podem ver todos acervos" ON acervos
  FOR SELECT
  USING (
    org_id IN (
      SELECT org_id FROM organization_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Membros da org podem criar acervos" ON acervos
  FOR INSERT
  WITH CHECK (
    org_id IN (
      SELECT org_id FROM organization_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Membros da org podem atualizar acervos" ON acervos
  FOR UPDATE
  USING (
    org_id IN (
      SELECT org_id FROM organization_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Membros da org podem deletar acervos" ON acervos
  FOR DELETE
  USING (
    org_id IN (
      SELECT org_id FROM organization_members WHERE user_id = auth.uid()
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
      JOIN organization_members om ON a.org_id = om.org_id
      WHERE om.user_id = auth.uid()
    )
  );

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
