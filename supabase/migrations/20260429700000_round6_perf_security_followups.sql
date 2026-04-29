-- 20260429700000_round6_perf_security_followups.sql
--
-- Round 6 follow-ups (a single migration covering the Round-5
-- regressions caught by the Round-6 audits):
--
-- 1. CRITICAL — Round-5 dropped agents_select_own and
--    agent_users_read_own thinking they were strict subsets of
--    agents_read_accessible / agent_users_manage_by_owner. They were
--    not — they were the recursion-breakers. Without them, every
--    authenticated query against /rest/v1/agents fails with 42P17
--    "infinite recursion detected in policy for relation agents".
--    See `20260429800000_fix_rls_recursion_agents.sql` (this migration's
--    same-step companion) — that one's already-applied via MCP. This
--    file ships the equivalent drop+create so a fresh install applies
--    them cleanly in order.
-- 2. Drop 3 indexes Round 5 created that turned out unused or
--    counter-productive (idx_dashboard_records_created_at_desc,
--    idx_agent_runs_status, health_metrics_user_time_idx).
-- 3. record_order_correction defense-in-depth — mirror cancel_order_
--    correction's pattern: every UPDATE/DELETE adds explicit
--    `WHERE user_id = auth.uid()`.

-- ─── 1. RLS recursion fix ───────────────────────────────────────────────

DROP POLICY IF EXISTS agents_read_accessible       ON public.agents;
DROP POLICY IF EXISTS agent_users_manage_by_owner  ON public.agent_users;

CREATE POLICY agents_select_own
  ON public.agents FOR SELECT TO authenticated
  USING (owner_id = (select auth.uid()));

CREATE POLICY agent_users_select_own
  ON public.agent_users FOR SELECT TO authenticated
  USING (user_id = (select auth.uid()));

-- ─── 2. Drop unused / counter-productive indexes ────────────────────────

DROP INDEX IF EXISTS public.idx_dashboard_records_created_at_desc;
DROP INDEX IF EXISTS public.idx_agent_runs_status;
DROP INDEX IF EXISTS public.health_metrics_user_time_idx;

-- ─── 3. record_order_correction defense-in-depth ────────────────────────

CREATE OR REPLACE FUNCTION public.record_order_correction(p_order_id uuid, p_kind text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_correction_id  uuid;
  v_user_id        uuid;
  v_trace          jsonb;
  v_source_emails  text[];
BEGIN
  IF p_kind NOT IN ('not_an_order','wrong_tracking','already_delivered') THEN
    RAISE EXCEPTION 'invalid correction kind: %', p_kind;
  END IF;

  SELECT user_id, parse_trace, source_email_ids
    INTO v_user_id, v_trace, v_source_emails
    FROM public.orders
    WHERE id = p_order_id;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'order not found: %', p_order_id;
  END IF;
  IF v_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'unauthorized: order belongs to another user';
  END IF;

  INSERT INTO public.order_corrections
    (user_id, order_id, kind, source_email_ids, parse_trace_snapshot)
    VALUES (v_user_id, p_order_id, p_kind, v_source_emails, v_trace)
    RETURNING id INTO v_correction_id;

  IF p_kind = 'not_an_order' THEN
    UPDATE public.orders
       SET status = 'dismissed_by_user',
           dismissed_at = now(),
           updated_at = now()
     WHERE id = p_order_id
       AND user_id = auth.uid();
    BEGIN
      PERFORM public.promote_merchant_rules(v_user_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'promote_merchant_rules failed for user %: %', v_user_id, SQLERRM;
    END;
  ELSIF p_kind = 'wrong_tracking' THEN
    UPDATE public.shipments
       SET tracking_number = NULL,
           carrier = NULL,
           tracking_url = NULL,
           updated_at = now()
     WHERE order_id = p_order_id
       AND EXISTS (SELECT 1 FROM public.orders o WHERE o.id = order_id AND o.user_id = auth.uid());
  ELSIF p_kind = 'already_delivered' THEN
    UPDATE public.orders
       SET manual_delivered_at = now(),
           updated_at = now()
     WHERE id = p_order_id
       AND user_id = auth.uid();
  END IF;

  RETURN v_correction_id;
END;
$function$;
