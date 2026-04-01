-- Migration: 005_orders_shipments
-- Orders Autopilot: Order + Shipment + ReviewItem model
-- Author: Claudinho / Minimax agent
-- Date: 2026-04-01

BEGIN;

-- ─────────────────────────────────────────────
-- ORDERS TABLE
-- A purchase confirmed by email
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.orders (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  merchant_name   TEXT NOT NULL,
  normalized_merchant TEXT NOT NULL,
  order_number    TEXT,
  order_date      TIMESTAMPTZ,
  total_amount    NUMERIC(12, 2),
  currency        TEXT DEFAULT 'USD',
  source_email_ids TEXT[] NOT NULL DEFAULT '{}',
  confidence_score NUMERIC(5, 4) NOT NULL DEFAULT 1.0,
  status          TEXT NOT NULL DEFAULT 'ordered'
                    CHECK (status IN (
                      'ordered', 'processing', 'shipped_partial',
                      'shipped', 'delivered', 'cancelled', 'issue'
                    )),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- SHIPMENTS TABLE
-- A single tracking number linked to an order
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.shipments (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id            UUID REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL,
  tracking_number     TEXT NOT NULL,
  carrier             TEXT,
  seventeen_track_id  TEXT,
  status              TEXT NOT NULL DEFAULT 'unknown'
                        CHECK (status IN (
                          'unknown', 'label_created', 'in_transit',
                          'out_for_delivery', 'delivered', 'exception'
                        )),
  latest_checkpoint   TEXT,
  shipped_at          TIMESTAMPTZ,
  delivered_at        TIMESTAMPTZ,
  source_email_ids    TEXT[] NOT NULL DEFAULT '{}',
  confidence_score    NUMERIC(5, 4) NOT NULL DEFAULT 1.0,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- REVIEW ITEMS TABLE
-- Ambiguous cases that need human review
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.review_items (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  type                TEXT NOT NULL
                        CHECK (type IN (
                          'duplicate_order', 'orphan_shipment', 'order_no_shipment',
                          'shipment_no_order', 'low_confidence_match', 'other'
                        )),
  related_order_id    UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  related_shipment_id UUID REFERENCES public.shipments(id) ON DELETE SET NULL,
  reason              TEXT NOT NULL,
  suggested_action    TEXT,
  confidence_score    NUMERIC(5, 4) NOT NULL DEFAULT 0.5,
  resolved_at         TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────
-- INDEXES
-- ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_orders_user_status     ON public.orders(user_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_normalized_merchant ON public.orders(normalized_merchant);
CREATE INDEX IF NOT EXISTS idx_orders_order_date     ON public.orders(order_date DESC);
CREATE INDEX IF NOT EXISTS idx_orders_created_at     ON public.orders(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_shipments_order_id     ON public.shipments(order_id);
CREATE INDEX IF NOT EXISTS idx_shipments_tracking     ON public.shipments(tracking_number);
CREATE INDEX IF NOT EXISTS idx_shipments_status       ON public.shipments(status);
CREATE INDEX IF NOT EXISTS idx_shipments_created_at   ON public.shipments(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_review_items_user_resolved ON public.review_items(user_id, resolved_at);
CREATE INDEX IF NOT EXISTS idx_review_items_created_at    ON public.review_items(created_at DESC);

-- ─────────────────────────────────────────────
-- AUTO-UPDATE TRIGGER
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_orders_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_orders_updated_at ON public.orders;
CREATE TRIGGER trigger_orders_updated_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.update_orders_updated_at();

DROP TRIGGER IF EXISTS trigger_shipments_updated_at ON public.shipments;
CREATE TRIGGER trigger_shipments_updated_at
  BEFORE UPDATE ON public.shipments
  FOR EACH ROW EXECUTE FUNCTION public.update_shipments_updated_at();

DROP TRIGGER IF EXISTS trigger_review_items_updated_at ON public.review_items;
CREATE TRIGGER trigger_review_items_updated_at
  BEFORE UPDATE ON public.review_items
  FOR EACH ROW EXECUTE FUNCTION public.update_review_items_updated_at();

-- ─────────────────────────────────────────────
-- ROW LEVEL SECURITY
-- ─────────────────────────────────────────────
ALTER TABLE public.orders      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipments  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.review_items ENABLE ROW LEVEL SECURITY;

-- Orders: users see their own
DROP POLICY IF EXISTS orders_select_own ON public.orders;
CREATE POLICY orders_select_own ON public.orders FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS orders_insert_own ON public.orders;
CREATE POLICY orders_insert_own ON public.orders FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS orders_update_own ON public.orders;
CREATE POLICY orders_update_own ON public.orders FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS orders_delete_own ON public.orders;
CREATE POLICY orders_delete_own ON public.orders FOR DELETE
  USING (user_id = auth.uid());

-- Shipments: users see their own via order join
DROP POLICY IF EXISTS shipments_select_own ON public.shipments;
CREATE POLICY shipments_select_own ON public.shipments FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = shipments.order_id AND o.user_id = auth.uid())
  );

DROP POLICY IF EXISTS shipments_insert_own ON public.shipments;
CREATE POLICY shipments_insert_own ON public.shipments FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = shipments.order_id AND o.user_id = auth.uid())
  );

DROP POLICY IF EXISTS shipments_update_own ON public.shipments;
CREATE POLICY shipments_update_own ON public.shipments FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = shipments.order_id AND o.user_id = auth.uid())
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = shipments.order_id AND o.user_id = auth.uid())
  );

DROP POLICY IF EXISTS shipments_delete_own ON public.shipments;
CREATE POLICY shipments_delete_own ON public.shipments FOR DELETE
  USING (
    EXISTS (SELECT 1 FROM public.orders o WHERE o.id = shipments.order_id AND o.user_id = auth.uid())
  );

-- Review items: users see their own
DROP POLICY IF EXISTS review_items_select_own ON public.review_items;
CREATE POLICY review_items_select_own ON public.review_items FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS review_items_insert_own ON public.review_items;
CREATE POLICY review_items_insert_own ON public.review_items FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS review_items_update_own ON public.review_items;
CREATE POLICY review_items_update_own ON public.review_items FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS review_items_delete_own ON public.review_items;
CREATE POLICY review_items_delete_own ON public.review_items FOR DELETE
  USING (user_id = auth.uid());

COMMIT;
