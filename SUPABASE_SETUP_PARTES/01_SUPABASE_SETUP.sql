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
