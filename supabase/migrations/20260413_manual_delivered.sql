-- Migration: 20260413_manual_delivered
-- Adds a user-controlled delivery override to orders.
-- When manual_delivered_at IS NOT NULL the client treats the order as delivered
-- regardless of what the automated tracking pipeline reports on `status`.
-- Automated agents MUST NOT write to this column; they only update `status`
-- and shipment tracking fields, so this override cannot be silently clobbered.
--
-- Reversible: setting manual_delivered_at back to NULL restores automatic tracking.

BEGIN;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS manual_delivered_at TIMESTAMPTZ DEFAULT NULL;

-- Partial index: only rows that are manually marked (fast override queries)
CREATE INDEX IF NOT EXISTS idx_orders_manual_delivered
  ON public.orders(manual_delivered_at)
  WHERE manual_delivered_at IS NOT NULL;

COMMIT;
