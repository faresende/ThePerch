-- 20260429100000_agent_runs_retention.sql
--
-- agent_runs grows ~200 rows/day across all ingest + insight crons.
-- Most rows are status='ok' heartbeats; errors and partials are the
-- diagnostically-valuable minority. Keep errors forever; prune ok
-- rows older than 90 days via a daily cron call to prune_agent_runs.

-- Partial index on the rare rows operators actually search for.
-- Lets `WHERE status <> 'ok'` queries stay O(log N) as ok rows pile up.
CREATE INDEX IF NOT EXISTS agent_runs_non_ok_idx
  ON public.agent_runs (started_at DESC)
  WHERE status <> 'ok';

-- Retention helper — pure DELETE wrapped in a function so the cron
-- entry can call it via PostgREST without raw-SQL access. Refuses
-- to prune anything younger than 7 days (safety bound).
CREATE OR REPLACE FUNCTION public.prune_agent_runs(
  p_days integer DEFAULT 90
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted integer := 0;
BEGIN
  IF p_days < 7 THEN
    RAISE EXCEPTION 'prune_agent_runs: refuse to prune anything younger than 7 days';
  END IF;
  DELETE FROM public.agent_runs
  WHERE status = 'ok'
    AND started_at < now() - (p_days || ' days')::interval;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

-- Service-role only: the function does an unscoped DELETE (no per-user
-- filter), so any 'authenticated' caller in a multi-user fork could wipe
-- everyone's status='ok' history. The retention cron worker runs under
-- the service-role key, so this restriction matches actual usage.
REVOKE EXECUTE ON FUNCTION public.prune_agent_runs(integer) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.prune_agent_runs(integer) TO service_role;
