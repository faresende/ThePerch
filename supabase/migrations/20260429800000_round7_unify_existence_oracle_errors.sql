-- 20260429800000_round7_unify_existence_oracle_errors.sql
--
-- Round 7 security audit caught an existence-oracle in
-- `record_order_correction` and `cancel_order_correction`. Both
-- functions raised distinct error messages for "row doesn't exist
-- anywhere" vs. "row exists in another user's data":
--
--   IF v_user_id IS NULL THEN RAISE EXCEPTION 'order not found: %', p_order_id;
--   IF v_user_id <> auth.uid() THEN RAISE EXCEPTION 'unauthorized: ...';
--
-- An authenticated stranger could pass any order_id and learn whether
-- it's a real order in someone else's tenant. UUIDs are 122-bit
-- random so brute-force isn't feasible, but if an attacker scrapes a
-- UUID from any side channel (URL, log, push payload), they can
-- confirm whether it's real.
--
-- Fix: collapse both branches into a single opaque message
-- ('order not accessible' / 'correction not accessible'). The
-- internal ownership check still gates the actual mutation; the
-- externally-visible message is unchanged regardless of which case
-- failed.

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

  IF v_user_id IS NULL OR v_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'order not accessible';
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

CREATE OR REPLACE FUNCTION public.cancel_order_correction(p_correction_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_correction record;
BEGIN
  SELECT * INTO v_correction
    FROM public.order_corrections
    WHERE id = p_correction_id;

  IF v_correction.user_id IS NULL OR v_correction.user_id <> auth.uid() THEN
    RAISE EXCEPTION 'correction not accessible';
  END IF;

  IF v_correction.kind = 'not_an_order' THEN
    UPDATE public.orders
       SET status = 'ordered',
           dismissed_at = NULL,
           updated_at = now()
     WHERE id = v_correction.order_id
       AND user_id = auth.uid();
  ELSIF v_correction.kind = 'already_delivered' THEN
    UPDATE public.orders
       SET manual_delivered_at = NULL,
           updated_at = now()
     WHERE id = v_correction.order_id
       AND user_id = auth.uid();
  END IF;

  DELETE FROM public.order_corrections
   WHERE id = p_correction_id
     AND user_id = auth.uid();
END;
$function$;

-- ALSO Round 7: 60s idle-in-transaction guardrail on user-facing
-- roles. Without this, a stuck transaction holds a Postgres
-- connection forever and can starve the pool.
ALTER ROLE authenticated SET idle_in_transaction_session_timeout = '60s';
ALTER ROLE anon          SET idle_in_transaction_session_timeout = '60s';
