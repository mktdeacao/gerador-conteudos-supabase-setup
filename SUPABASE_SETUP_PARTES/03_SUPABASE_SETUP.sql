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
