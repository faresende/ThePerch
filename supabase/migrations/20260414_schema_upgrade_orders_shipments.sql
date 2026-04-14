-- Migration: 20260414_schema_upgrade_orders_shipments
-- Additive / idempotent upgrade for legacy orders + shipments tables.
--
-- Problem: The original CREATE TABLE IF NOT EXISTS migration (005) does nothing
-- if the tables already exist from the legacy 20260331 schema. This migration
-- explicitly adds all columns, indexes, triggers, policies, and tables that
-- the current codebase expects but a legacy database may be missing.
--
-- Safety rules:
--   • ADD COLUMN IF NOT EXISTS only — never drops or renames columns.
--   • CREATE TABLE IF NOT EXISTS for review_items.
--   • CREATE INDEX IF NOT EXISTS everywhere.
--   • CREATE OR REPLACE for functions; DROP TRIGGER IF EXISTS before CREATE.
--   • DROP POLICY IF EXISTS before CREATE POLICY (idempotent re-run).
--   • No data is rewritten or backfilled. New columns remain NULL until
--     future writes populate them.
--   • Does NOT apply itself — must be run manually after review.
--
-- Author: Claude / Fabio
-- Date: 2026-04-14

BEGIN;

-- ═══════════════════════════════════════════════════════════════
-- 1. ORDERS TABLE — add missing columns
-- ═══════════════════════════════════════════════════════════════

-- user_id: legacy table had no user scoping. Added nullable because existing
-- rows cannot be backfilled automatically. New inserts should always set this.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES public.users(id) ON DELETE CASCADE;

-- merchant_name / normalized_merchant: legacy used a single "merchant" column.
-- We add the new columns alongside it; the old column is left untouched.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS merchant_name TEXT;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS normalized_merchant TEXT;

-- order_date: legacy table had no date field.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS order_date TIMESTAMPTZ;

-- total_amount: legacy used "total". Add the new name alongside.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS total_amount NUMERIC(12, 2);

-- source_email_ids (array): legacy used singular "source_email_id" TEXT.
-- New column is the array variant; old column left in place.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS source_email_ids TEXT[] DEFAULT '{}';

-- confidence_score: legacy used "confidence" NUMERIC(4,3).
-- Add new column alongside; old column left in place.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS confidence_score NUMERIC(5, 4) DEFAULT 1.0;

-- updated_at: legacy had no update timestamp.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- manual_delivered_at: user-controlled delivery override (from 20260413).
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS manual_delivered_at TIMESTAMPTZ DEFAULT NULL;

-- ═══════════════════════════════════════════════════════════════
-- 2. SHIPMENTS TABLE — add missing columns
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.shipments
  ADD COLUMN IF NOT EXISTS seventeen_track_id TEXT;

ALTER TABLE public.shipments
  ADD COLUMN IF NOT EXISTS latest_checkpoint TEXT;

ALTER TABLE public.shipments
  ADD COLUMN IF NOT EXISTS shipped_at TIMESTAMPTZ;

ALTER TABLE public.shipments
  ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;

ALTER TABLE public.shipments
  ADD COLUMN IF NOT EXISTS source_email_ids TEXT[] DEFAULT '{}';

ALTER TABLE public.shipments
  ADD COLUMN IF NOT EXISTS confidence_score NUMERIC(5, 4) DEFAULT 1.0;

ALTER TABLE public.shipments
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- ═══════════════════════════════════════════════════════════════
-- 3. REVIEW_ITEMS TABLE — create if missing (legacy had none)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.review_items (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  type                TEXT NOT NULL
                        CHECK (type IN (
                          'duplicate_order', 'orphan_shipment', 'order_no_shipment',
                          'shipment_no_order', 'low_confidence_match',
                          'ambiguous_order_match', 'missing_order_for_tracking',
                          'missing_tracking_for_order', 'other'
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

-- If review_items already exists but has a stale CHECK constraint missing
-- the newer types, drop and re-add it. (DROP CONSTRAINT IF EXISTS is safe.)
-- NOTE: constraint name "review_items_type_check" is the Postgres auto-name.
ALTER TABLE public.review_items
  DROP CONSTRAINT IF EXISTS review_items_type_check;

ALTER TABLE public.review_items
  ADD CONSTRAINT review_items_type_check
    CHECK (type IN (
      'duplicate_order', 'orphan_shipment', 'order_no_shipment',
      'shipment_no_order', 'low_confidence_match',
      'ambiguous_order_match', 'missing_order_for_tracking',
      'missing_tracking_for_order', 'other'
    ));

-- ═══════════════════════════════════════════════════════════════
-- 4. INDEXES — create if missing
-- ═══════════════════════════════════════════════════════════════

-- Orders
CREATE INDEX IF NOT EXISTS idx_orders_user_status
  ON public.orders(user_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_normalized_merchant
  ON public.orders(normalized_merchant);
CREATE INDEX IF NOT EXISTS idx_orders_order_date
  ON public.orders(order_date DESC);
CREATE INDEX IF NOT EXISTS idx_orders_created_at
  ON public.orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_manual_delivered
  ON public.orders(manual_delivered_at)
  WHERE manual_delivered_at IS NOT NULL;

-- Shipments
CREATE INDEX IF NOT EXISTS idx_shipments_order_id
  ON public.shipments(order_id);
CREATE INDEX IF NOT EXISTS idx_shipments_tracking
  ON public.shipments(tracking_number);
CREATE INDEX IF NOT EXISTS idx_shipments_status
  ON public.shipments(status);
CREATE INDEX IF NOT EXISTS idx_shipments_created_at
  ON public.shipments(created_at DESC);

-- Review items
CREATE INDEX IF NOT EXISTS idx_review_items_user_resolved
  ON public.review_items(user_id, resolved_at);
CREATE INDEX IF NOT EXISTS idx_review_items_created_at
  ON public.review_items(created_at DESC);

-- ═══════════════════════════════════════════════════════════════
-- 5. AUTO-UPDATE TRIGGERS — create / replace idempotently
-- ═══════════════════════════════════════════════════════════════

-- Shared trigger function (one function, reused for all three tables)
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Also create the table-specific function names that 005 references,
-- so the old triggers don't break if they already exist.
CREATE OR REPLACE FUNCTION public.update_orders_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.update_shipments_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.update_review_items_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

-- Drop and recreate triggers (idempotent)
DROP TRIGGER IF EXISTS trigger_orders_updated_at ON public.orders;
CREATE TRIGGER trigger_orders_updated_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_shipments_updated_at ON public.shipments;
CREATE TRIGGER trigger_shipments_updated_at
  BEFORE UPDATE ON public.shipments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trigger_review_items_updated_at ON public.review_items;
CREATE TRIGGER trigger_review_items_updated_at
  BEFORE UPDATE ON public.review_items
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ═══════════════════════════════════════════════════════════════
-- 6. ROW LEVEL SECURITY — enable + idempotent policies
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.orders       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipments    ENABLE ROW LEVEL SECURITY;
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

-- ═══════════════════════════════════════════════════════════════
-- 7. DOCUMENTATION: columns that remain NULL until future writes
-- ═══════════════════════════════════════════════════════════════
-- The following columns are added but NOT backfilled by this migration:
--
--   orders.user_id             — legacy rows have no user association.
--                                Future inserts from Orders Autopilot always set this.
--   orders.merchant_name       — legacy uses "merchant" column instead.
--   orders.normalized_merchant — same as above.
--   orders.order_date          — legacy had no date.
--   orders.total_amount        — legacy uses "total" column instead.
--   orders.source_email_ids    — legacy uses singular "source_email_id".
--   orders.confidence_score    — legacy uses "confidence" with lower precision.
--
-- A future data-backfill migration can copy:
--   merchant      → merchant_name, normalize → normalized_merchant
--   total         → total_amount
--   source_email_id → ARRAY[source_email_id] into source_email_ids
--   confidence    → confidence_score
-- but that requires a maintenance window and is NOT done here.

COMMIT;
