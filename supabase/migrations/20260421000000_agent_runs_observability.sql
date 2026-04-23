-- Observability table for pipeline runs (crons, agents, aggregators).
-- Single source of truth for "did pipeline X run successfully, and when?".
-- Every wrapper script that runs a pipeline brackets the run with
-- start_agent_run() / end_agent_run() helpers via cli.js record-run.

BEGIN;

CREATE TABLE IF NOT EXISTS public.agent_runs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id      text NOT NULL,
  run_type      text NOT NULL,                       -- 'ingest', 'poll', 'aggregate', 'sync', 'other'
  started_at    timestamptz NOT NULL DEFAULT now(),
  ended_at      timestamptz,
  status        text NOT NULL DEFAULT 'running'
                  CHECK (status IN ('running', 'ok', 'error', 'partial', 'timeout')),
  summary       jsonb,
  error_detail  text
);

CREATE INDEX IF NOT EXISTS idx_agent_runs_agent_started
  ON public.agent_runs (agent_id, started_at DESC);

-- Partial index for the common "what's broken" query.
CREATE INDEX IF NOT EXISTS idx_agent_runs_status
  ON public.agent_runs (status, started_at DESC)
  WHERE status <> 'ok';

-- Latest-status-per-agent convenience view.
CREATE OR REPLACE VIEW public.agent_runs_latest AS
SELECT DISTINCT ON (agent_id, run_type)
  agent_id, run_type, started_at, ended_at, status, summary, error_detail
FROM public.agent_runs
ORDER BY agent_id, run_type, started_at DESC;

-- RLS: service_role bypasses, authenticated users see only their own agents'
-- runs (via agents.owner_id). Service inserts of rows for agents without a
-- matching row in public.agents are visible to all authenticated users.
ALTER TABLE public.agent_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role all" ON public.agent_runs;
CREATE POLICY "service_role all"
  ON public.agent_runs
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "authenticated select own" ON public.agent_runs;
CREATE POLICY "authenticated select own"
  ON public.agent_runs
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.agents a
      WHERE a.id = agent_runs.agent_id
      AND (a.owner_id IS NULL OR a.owner_id = auth.uid())
    )
    OR agent_runs.agent_id NOT IN (SELECT id FROM public.agents)
  );

COMMIT;
