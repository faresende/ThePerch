-- 20260429122429_prune_agent_runs_lock.sql
--
-- Stub committed in Round 11 to match the prod migration ledger.
-- prune_agent_runs is unscoped (deletes status='ok' rows for ALL users
-- in a multi-user fork). Lock execution to service_role only.

REVOKE EXECUTE ON FUNCTION public.prune_agent_runs(integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.prune_agent_runs(integer) TO service_role;
