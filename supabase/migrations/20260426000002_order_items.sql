-- ============================================================================
-- 20260426000002_order_items.sql
--
-- Tier 4 of the orders-autopilot: per-line-item extraction.
--
-- Each row in `public.order_items` is one line on a customer's order
-- — typically one product purchased, with name + quantity + unit
-- price. Extracted by the LLM from the email body whenever the
-- autopilot creates / updates an order. The iOS card uses these to
-- render an expandable detail view ("1× Hardgraft Tasche bag · 1×
-- leather strap").
--
-- Why a separate table (vs JSONB column on orders):
--   * Future-proof for queries: "what did I buy in 2026", "did I
--     already order this?", "spend by category" all need item-level
--     joins. A JSONB column would close those doors.
--   * Items are an independent lifecycle from the order itself —
--     we can re-extract or correct items without touching the order.
--   * Standard relational shape; iOS modelling is straightforward.
--
-- Security: RLS enforced via the parent order's user_id. An item
-- belongs to whoever owns the parent row.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.order_items (
  id            uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id      uuid          NOT NULL
                              REFERENCES public.orders(id) ON DELETE CASCADE,
  name          text          NOT NULL CHECK (length(name) > 0),
  quantity      numeric       NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price    numeric,
  currency      text,
  position      int           NOT NULL DEFAULT 0,
  raw_line      text,
  created_at    timestamptz   NOT NULL DEFAULT now(),
  updated_at    timestamptz   NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.order_items IS
  'Per-line-item extraction for tracked orders. One row per product '
  'on the order. Populated by the LLM when the orders-autopilot '
  'classifies an email as a purchase_confirmation, re-extractable '
  'whenever needed.';

COMMENT ON COLUMN public.order_items.position IS
  'Display position within the parent order. Preserved so the iOS '
  'card renders items in the same order they appeared in the email.';

COMMENT ON COLUMN public.order_items.raw_line IS
  'Original line as it appeared in the email body (when the LLM '
  'returned it). Useful for debugging extraction quality without '
  're-fetching the source email from JMAP.';

-- Most queries are "items for this order", in display order.
CREATE INDEX IF NOT EXISTS order_items_order_id_position_idx
  ON public.order_items (order_id, position);

-- ─── RLS ─────────────────────────────────────────────────────────────────────
--
-- Items are scoped through the parent order's user_id. The policy uses
-- a subquery rather than denormalising user_id onto items — a single
-- order's user_id never changes (FK + ON DELETE CASCADE) so the
-- subquery is fast and avoids the "two sources of truth" failure mode.

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS order_items_select_own ON public.order_items;
DROP POLICY IF EXISTS order_items_insert_own ON public.order_items;
DROP POLICY IF EXISTS order_items_update_own ON public.order_items;
DROP POLICY IF EXISTS order_items_delete_own ON public.order_items;

CREATE POLICY order_items_select_own
  ON public.order_items FOR SELECT
  TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id = order_items.order_id AND o.user_id = auth.uid()
  ));

CREATE POLICY order_items_insert_own
  ON public.order_items FOR INSERT
  TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id = order_items.order_id AND o.user_id = auth.uid()
  ));

CREATE POLICY order_items_update_own
  ON public.order_items FOR UPDATE
  TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id = order_items.order_id AND o.user_id = auth.uid()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id = order_items.order_id AND o.user_id = auth.uid()
  ));

CREATE POLICY order_items_delete_own
  ON public.order_items FOR DELETE
  TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id = order_items.order_id AND o.user_id = auth.uid()
  ));

-- ─── updated_at trigger ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.update_order_items_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS order_items_updated_at_trigger ON public.order_items;

CREATE TRIGGER order_items_updated_at_trigger
  BEFORE UPDATE ON public.order_items
  FOR EACH ROW
  EXECUTE FUNCTION public.update_order_items_updated_at();

COMMIT;
