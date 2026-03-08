-- ==========================================================================
-- The Perch - Enable RLS + Policies (beta multi-tenant hardening)
--
-- NOTE:
-- - Do NOT run automatically.
-- - Service role key bypasses RLS automatically (Supabase behavior).
-- - This file is intentionally idempotent where possible.
-- ==========================================================================

-- Ensure RLS is enabled on core tables
ALTER TABLE IF EXISTS public.records ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.token_usage ENABLE ROW LEVEL SECURITY;

-- RECORDS
DROP POLICY IF EXISTS records_select_own ON public.records;
CREATE POLICY records_select_own
  ON public.records FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS records_insert_own ON public.records;
CREATE POLICY records_insert_own
  ON public.records FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS records_update_own ON public.records;
CREATE POLICY records_update_own
  ON public.records FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS records_delete_own ON public.records;
CREATE POLICY records_delete_own
  ON public.records FOR DELETE
  USING (user_id = auth.uid());

-- AGENTS (owner_id)
DROP POLICY IF EXISTS agents_select_own ON public.agents;
CREATE POLICY agents_select_own
  ON public.agents FOR SELECT
  USING (owner_id = auth.uid());

DROP POLICY IF EXISTS agents_insert_own ON public.agents;
CREATE POLICY agents_insert_own
  ON public.agents FOR INSERT
  WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS agents_update_own ON public.agents;
CREATE POLICY agents_update_own
  ON public.agents FOR UPDATE
  USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS agents_delete_own ON public.agents;
CREATE POLICY agents_delete_own
  ON public.agents FOR DELETE
  USING (owner_id = auth.uid());

-- TOKEN_USAGE
-- Requires token_usage.user_id column (added in a later migration).
DROP POLICY IF EXISTS token_usage_select_own ON public.token_usage;
CREATE POLICY token_usage_select_own
  ON public.token_usage FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS token_usage_insert_own ON public.token_usage;
CREATE POLICY token_usage_insert_own
  ON public.token_usage FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS token_usage_update_own ON public.token_usage;
CREATE POLICY token_usage_update_own
  ON public.token_usage FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS token_usage_delete_own ON public.token_usage;
CREATE POLICY token_usage_delete_own
  ON public.token_usage FOR DELETE
  USING (user_id = auth.uid());
