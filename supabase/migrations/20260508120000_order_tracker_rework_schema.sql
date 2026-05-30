-- 20260508120000_order_tracker_rework_schema.sql
-- Order Tracker Rework: package-primary model.
-- Spec: docs/superpowers/specs/2026-05-08-order-tracker-rework-design.md

BEGIN;

-- ── orders: classification + hide-not-delete ──────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS classification text,
  ADD COLUMN IF NOT EXISTS hidden boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS hidden_reason text;

ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_classification_check;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_classification_check
  CHECK (classification IS NULL OR classification IN ('physical','digital','unsure'));

CREATE INDEX IF NOT EXISTS orders_user_visible_idx
  ON public.orders (user_id, hidden, classification)
  WHERE hidden = false;

-- ── shipments: real-tracking-only invariant + eta source ──────────────
ALTER TABLE public.shipments
  ADD COLUMN IF NOT EXISTS eta_source text;
-- Drop the legacy constraint FIRST: its old vocabulary ('17track','carrier_email')
-- would reject the normalization UPDATE below before the new constraint is in place.
ALTER TABLE public.shipments
  DROP CONSTRAINT IF EXISTS shipments_eta_source_check;
-- Normalize the pre-existing legacy value to the new ladder's vocabulary.
-- 'carrier_email' == the 'email' tier (ETA parsed from the shipping email).
UPDATE public.shipments SET eta_source = 'email' WHERE eta_source = 'carrier_email';
ALTER TABLE public.shipments
  ADD CONSTRAINT shipments_eta_source_check
  CHECK (eta_source IS NULL OR eta_source IN ('email','17track','heuristic'));

-- NOTE: the partial unique index on (user_id, tracking_number) is created
-- in a LATER migration (20260508130000) AFTER the backfill de-duplicates
-- and removes empty-tracking rows — creating it here would fail on the
-- existing duplicate/empty rows.

-- ── merchant_rules: new physical/digital actions ──────────────────────
ALTER TABLE public.merchant_rules
  DROP CONSTRAINT IF EXISTS merchant_rules_action_check;
ALTER TABLE public.merchant_rules
  ADD CONSTRAINT merchant_rules_action_check
  CHECK (action IN ('skip_purchase','always_physical','always_digital'));

COMMIT;
