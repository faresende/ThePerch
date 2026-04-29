-- 20260429300000_agent_runs_rls_tighten.sql
--
-- Pre-public Round 3 security pass — tighten the agent_runs SELECT
-- policy. The original migration's policy had two cross-tenant escape
-- hatches that the maintainer's single-user installation didn't expose
-- but that would leak in any multi-user fork:
--
--   (a) `a.owner_id IS NULL OR a.owner_id = auth.uid()` — the IS-NULL
--       branch is dead today (agents.owner_id is NOT NULL) but ready
--       to footgun anyone who relaxes that constraint.
--   (b) `agent_runs.agent_id NOT IN (SELECT id FROM agents)` — exposes
--       every agent_runs row whose agent_id hasn't been registered in
--       public.agents yet. Race window during _ensure_agent_registered
--       on first ingest, plus any agent_id naming conflict.
--
-- New policy: strict owner match. Service-role bypasses RLS so the
-- ingest workers still write fine.

DROP POLICY IF EXISTS "authenticated select own" ON public.agent_runs;
CREATE POLICY "authenticated select own"
  ON public.agent_runs
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = agent_runs.agent_id
        AND a.owner_id = auth.uid()
    )
  );
