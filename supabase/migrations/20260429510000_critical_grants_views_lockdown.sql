-- 20260429510000_critical_grants_views_lockdown.sql
--
-- Round-4 security pass — second batch.
--
-- 1. SECURITY DEFINER functions: REVOKE EXECUTE from PUBLIC + anon. Each
--    function is then GRANTed back to the role(s) that legitimately need
--    it (authenticated for user-facing RPCs, service_role only for the
--    destructive prune_*).
--
--    The standout was `prune_agent_runs_older_than(days)` — anon could
--    call `POST /rest/v1/rpc/prune_agent_runs_older_than?days=7` and
--    delete every agent_runs row older than 7 days. Pure DoS lever.
--
-- 2. Drop `prune_agent_runs_older_than` entirely — it duplicates
--    `prune_agent_runs(p_days)` which has the proper service_role lock.
--
-- 3. SECURITY DEFINER views (`agent_runs_latest`, `active_shipments_summary`)
--    bypass RLS because they execute under the view-owner's privileges.
--    Switch to `security_invoker = true` so the caller's RLS applies.
--
-- 4. records dual INSERT policy — `records_insert_agent_owner` did not
--    check `user_id = auth.uid()`, so any user with their own agent
--    could insert a row with `user_id = victim, agent_id = my_agent`,
--    then read it back via `records_read_own`. Fix by adding the
--    `user_id = auth.uid()` clause to the policy.
--
-- 5. records duplicate UPDATE policy — `records_update_own_pin` was an
--    exact duplicate of `records_update_own`. Drop it.
--
-- 6. Mutable search_path on trigger functions — set explicitly to
--    `public, pg_temp` so an attacker-controlled `pg_temp` schema can't
--    hijack `now()` / `current_timestamp` resolution.

-- ─── 1+2. Function grant lockdown ───────────────────────────────────────

REVOKE EXECUTE ON FUNCTION public.apply_merchant_rule(uuid, text, text)         FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.promote_merchant_rules(uuid)                  FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.cancel_order_correction(uuid)                 FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.record_order_correction(uuid, text)           FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.prune_agent_runs(integer)                     FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable()                             FROM PUBLIC, anon, authenticated;

-- prune_agent_runs_older_than: drop entirely. Duplicate of prune_agent_runs.
DROP FUNCTION IF EXISTS public.prune_agent_runs_older_than(integer);

-- ─── 3. SECURITY DEFINER views → security_invoker ───────────────────────

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_views WHERE schemaname = 'public' AND viewname = 'agent_runs_latest') THEN
    EXECUTE 'ALTER VIEW public.agent_runs_latest SET (security_invoker = true)';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_views WHERE schemaname = 'public' AND viewname = 'active_shipments_summary') THEN
    EXECUTE 'ALTER VIEW public.active_shipments_summary SET (security_invoker = true)';
  END IF;
END;
$$;

-- ─── 4. records INSERT-via-own-agent escalation fix ────────────────────

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'records' AND policyname = 'records_insert_agent_owner') THEN
    DROP POLICY records_insert_agent_owner ON public.records;
  END IF;
END;
$$;

CREATE POLICY records_insert_agent_owner
  ON public.records FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (select auth.uid())
    AND agent_id IN (SELECT id FROM public.agents WHERE owner_id = (select auth.uid()))
  );

-- ─── 5. records duplicate UPDATE policy ────────────────────────────────

DROP POLICY IF EXISTS records_update_own_pin ON public.records;

-- ─── 6. Trigger function search_path lockdown ──────────────────────────

DO $$
DECLARE
  fn_name text;
BEGIN
  FOR fn_name IN SELECT unnest(ARRAY[
    'merchant_rules_touch_updated_at',
    'update_food_memories_updated_at',
    'set_updated_at',
    'update_orders_updated_at',
    'update_shipments_updated_at',
    'update_review_items_updated_at',
    'update_records_updated_at'
  ])
  LOOP
    IF EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = fn_name) THEN
      EXECUTE format('ALTER FUNCTION public.%I() SET search_path = public, pg_temp', fn_name);
    END IF;
  END LOOP;
END;
$$;
