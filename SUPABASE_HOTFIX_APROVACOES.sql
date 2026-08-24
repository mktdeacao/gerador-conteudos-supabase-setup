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
