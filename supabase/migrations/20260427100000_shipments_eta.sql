-- ============================================================================
-- 20260427100000_shipments_eta.sql
--
-- Estimated delivery date on shipments. Sourced from carrier shipping
-- email regex extraction OR 17track polling, with a shared resolver
-- (in scanner code) applying priority + recency tie-break.
--
-- See docs/superpowers/specs/2026-04-27-orders-eta-design.md.
-- ============================================================================

BEGIN;

ALTER TABLE public.shipments
  ADD COLUMN IF NOT EXISTS eta_at          timestamptz,
  ADD COLUMN IF NOT EXISTS eta_source      text,
  ADD COLUMN IF NOT EXISTS eta_recorded_at timestamptz;

-- Constrain eta_source to the two sources we currently extract from.
-- merchant_llm reserved for Phase 1.5 (would require placeholder-shipment
-- pattern; out of scope for v1).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'shipments_eta_source_check'
  ) THEN
    ALTER TABLE public.shipments
      ADD CONSTRAINT shipments_eta_source_check
      CHECK (eta_source IS NULL OR eta_source IN ('17track', 'carrier_email'));
  END IF;
END $$;

COMMENT ON COLUMN public.shipments.eta_at IS
  'Estimated delivery date for this shipment. Set by carrier-email regex
   extraction (handleShippingNotification) or 17track polling. Resolved
   via scanner-side priority rule (17track > carrier_email; same source
   → newer eta_recorded_at wins). NULL when no ETA source has provided
   one yet, or for legacy rows. Reversed if user records a "wrong eta"
   correction (Phase 2).';

COMMENT ON COLUMN public.shipments.eta_source IS
  'Which extractor set the current eta_at value. Used by the scanner-side
   resolver to apply priority rules on subsequent writes.';

COMMENT ON COLUMN public.shipments.eta_recorded_at IS
  'When the current eta_at value was written. Used as tie-break in the
   resolver when both current and incoming have the same eta_source.';

-- Partial index for the iOS rollup query: "earliest non-delivered ETA
-- per order." Filtered to non-null + non-delivered so the index size
-- matches the active set rather than the full shipments table.
CREATE INDEX IF NOT EXISTS shipments_active_eta_idx
  ON public.shipments (order_id, eta_at)
  WHERE eta_at IS NOT NULL AND delivered_at IS NULL;

COMMIT;
