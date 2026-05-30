-- 20260508130000_shipments_unique_tracking.sql
-- Run ONLY after backfill-tracker --apply has de-duplicated + removed
-- empty-tracking shipment rows, else this index creation fails.
CREATE UNIQUE INDEX IF NOT EXISTS shipments_user_tracking_uniq
  ON public.shipments (user_id, tracking_number)
  WHERE tracking_number <> '';
