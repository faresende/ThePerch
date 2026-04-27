-- ============================================================================
-- 20260427000000_order_corrections.sql
--
-- Corrections-and-rules feedback loop — Phase 1 capture layer.
--
-- Adds:
--   1. orders.parse_trace (jsonb)        — per-order audit trail of every
--                                          decision the parser made (classifier
--                                          path, merchant candidates,
--                                          physical/digital signals, tracking
--                                          candidates with discarded_reason).
--   2. orders.dismissed_at (timestamptz) — set when user swipes "not an order".
--   3. order_corrections table           — one row per user-disagreement with
--                                          the parser. Snapshots the order's
--                                          parse_trace at correction time so
--                                          the rule-distillation engine
--                                          (Phase 2) has stable training data
--                                          even if the row is later re-parsed.
--   4. record_order_correction RPC       — atomic insert + state transition
--                                          per correction kind.
--   5. cancel_order_correction RPC       — symmetric undo.
--
-- See docs/superpowers/specs/2026-04-27-orders-corrections-and-rules-design.md
-- for design rationale and Phase 2/3 hooks.
-- ============================================================================

BEGIN;

-- ─── 1. orders: parse_trace + dismissed_at ────────────────────────────────

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS parse_trace  jsonb,
  ADD COLUMN IF NOT EXISTS dismissed_at timestamptz;

COMMENT ON COLUMN public.orders.parse_trace IS
  'Audit trail of parser decisions for this order. Schema in design spec
   2026-04-27-orders-corrections-and-rules-design.md. NULL for legacy rows.';

COMMENT ON COLUMN public.orders.dismissed_at IS
  'Set when user swipes "not an order" via OrdersService.recordCorrection.
   Coupled with status=''dismissed_by_user''. Reversed by cancel_order_correction.';

-- status column already accepts free text — no DDL change. New values:
--   'digital'           — Apple-bug fix; digital purchase, no shipment row
--   'dismissed_by_user' — soft-deleted via "Not an order" correction


-- ─── 2. order_corrections table ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.order_corrections (
  id                   uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              uuid          NOT NULL
                                     REFERENCES public.users(id) ON DELETE CASCADE,
  order_id             uuid          REFERENCES public.orders(id) ON DELETE SET NULL,
  kind                 text          NOT NULL
                                     CHECK (kind IN ('not_an_order',
                                                     'wrong_tracking',
                                                     'already_delivered')),
  source_email_ids     text[],
  parse_trace_snapshot jsonb,
  notes                text,
  created_at           timestamptz   NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.order_corrections IS
  'One row per user-disagreement with the orders parser. Phase 1 capture
   layer. parse_trace_snapshot is a copy of the order''s parse_trace at
   correction time so Phase 2 rule distillation has stable training data.';

CREATE INDEX IF NOT EXISTS order_corrections_user_kind_created_idx
  ON public.order_corrections (user_id, kind, created_at DESC);

CREATE INDEX IF NOT EXISTS order_corrections_order_idx
  ON public.order_corrections (order_id)
  WHERE order_id IS NOT NULL;

ALTER TABLE public.order_corrections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS order_corrections_select_own ON public.order_corrections;
DROP POLICY IF EXISTS order_corrections_insert_own ON public.order_corrections;
DROP POLICY IF EXISTS order_corrections_update_own ON public.order_corrections;
DROP POLICY IF EXISTS order_corrections_delete_own ON public.order_corrections;

CREATE POLICY order_corrections_select_own
  ON public.order_corrections FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY order_corrections_insert_own
  ON public.order_corrections FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY order_corrections_update_own
  ON public.order_corrections FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY order_corrections_delete_own
  ON public.order_corrections FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);


-- ─── 3. record_order_correction RPC ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.record_order_correction(
  p_order_id uuid,
  p_kind     text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  -- State transition per kind
  IF p_kind = 'not_an_order' THEN
    UPDATE public.orders
       SET status = 'dismissed_by_user',
           dismissed_at = now(),
           updated_at = now()
     WHERE id = p_order_id;

  ELSIF p_kind = 'wrong_tracking' THEN
    UPDATE public.shipments
       SET tracking_number = NULL,
           carrier = NULL,
           tracking_url = NULL,
           updated_at = now()
     WHERE order_id = p_order_id;

  ELSIF p_kind = 'already_delivered' THEN
    UPDATE public.orders
       SET manual_delivered_at = now(),
           updated_at = now()
     WHERE id = p_order_id;
  END IF;

  RETURN v_correction_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_order_correction(uuid, text)
  TO authenticated;


-- ─── 4. cancel_order_correction RPC ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cancel_order_correction(
  p_correction_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  -- Reverse state transition per kind
  IF v_correction.kind = 'not_an_order' THEN
    UPDATE public.orders
       SET status = 'ordered',
           dismissed_at = NULL,
           updated_at = now()
     WHERE id = v_correction.order_id;

  ELSIF v_correction.kind = 'already_delivered' THEN
    UPDATE public.orders
       SET manual_delivered_at = NULL,
           updated_at = now()
     WHERE id = v_correction.order_id;

  -- 'wrong_tracking' is not symmetrically reversible without a re-scan.
  -- Tracking stays nulled; user re-scans the carrier email to restore it.
  END IF;

  DELETE FROM public.order_corrections WHERE id = p_correction_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_order_correction(uuid)
  TO authenticated;

COMMIT;
