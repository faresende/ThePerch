-- 20260429430000_email_classifications_retention.sql
--
-- Mirror of agent_runs retention: email_classifications can grow without
-- bound (every commerce email scanned by the autopilot writes a row, even
-- the ones we skip). Add a service-role-only RPC that prunes rows older
-- than `days`, and rely on cron to fire it daily.
--
-- The RPC is locked to `service_role` so a leaked anon key can never
-- mass-delete classification history.

CREATE OR REPLACE FUNCTION public.prune_email_classifications(days integer DEFAULT 90)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted integer;
BEGIN
  DELETE FROM public.email_classifications
  WHERE classified_at < (now() - (days || ' days')::interval);

  GET DIAGNOSTICS deleted = ROW_COUNT;
  RETURN deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.prune_email_classifications(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.prune_email_classifications(integer) FROM authenticated;
REVOKE ALL ON FUNCTION public.prune_email_classifications(integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.prune_email_classifications(integer) TO service_role;

COMMENT ON FUNCTION public.prune_email_classifications(integer) IS
  'Delete email_classifications rows older than `days` (default 90). service_role only — call from a daily cron, mirroring prune_agent_runs.';
