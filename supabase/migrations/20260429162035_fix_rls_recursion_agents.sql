-- 20260429162035_fix_rls_recursion_agents.sql
--
-- Stub committed in Round 11 to match the prod migration ledger.
-- Round 5's policy consolidation deleted the simple non-recursive policies
-- and left a cycle:
--   agents_read_accessible(SELECT) reads agent_users
--   agent_users_manage_by_owner(ALL) reads agents
-- Postgres aborted every authenticated query with 42P17 "infinite recursion".
-- Fix: drop both recursive policies, replace with non-recursive owner-only
-- ones. This migration is also re-applied by R6's
-- 20260429700000_round6_perf_security_followups.sql, so it's idempotent
-- on a fresh install regardless of order.

DROP POLICY IF EXISTS agents_read_accessible       ON public.agents;
DROP POLICY IF EXISTS agent_users_manage_by_owner  ON public.agent_users;

DROP POLICY IF EXISTS agents_select_own            ON public.agents;
CREATE POLICY agents_select_own
  ON public.agents FOR SELECT TO authenticated
  USING (owner_id = (select auth.uid()));

DROP POLICY IF EXISTS agent_users_select_own       ON public.agent_users;
CREATE POLICY agent_users_select_own
  ON public.agent_users FOR SELECT TO authenticated
  USING (user_id = (select auth.uid()));
