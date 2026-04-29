-- 20260429610000_cancel_order_correction_defense_in_depth.sql
--
-- Round-5 security audit caught a latent IDOR-shape risk in
-- `cancel_order_correction`: it checked `order_corrections.user_id =
-- auth.uid()` (good) but then UPDATE'd `public.orders` based on the
-- correction's `order_id` without a separate `orders.user_id =
-- auth.uid()` check. Today the invariant (orders.user_id always
-- matches order_corrections.user_id) is enforced by
-- `record_order_correction`, but a future migration that opens a new
-- INSERT path would silently let user A cancel a correction whose
-- order belongs to user B.
--
-- Each UPDATE/DELETE inside the function now adds an explicit
-- `WHERE user_id = auth.uid()` so the cross-tenant boundary holds
-- regardless of upstream invariant drift.

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

  IF v_correction.user_id IS NULL THEN
    RAISE EXCEPTION 'correction not found: %', p_correction_id;
  END IF;
  IF v_correction.user_id <> auth.uid() THEN
    RAISE EXCEPTION 'unauthorized';
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

  -- 'wrong_tracking' is not symmetrically reversible without a re-scan.
  END IF;

  DELETE FROM public.order_corrections
   WHERE id = p_correction_id
     AND user_id = auth.uid();
END;
$function$;
