-- 20260508130000_shipments_unique_tracking.sql
-- Run ONLY after backfill-tracker --apply has de-duplicated + removed
-- empty-tracking shipment rows, else this index creation fails.
-- shipments has no user_id column (scopes via order_id → orders.user_id);
-- tracking numbers are globally unique, so the index is on tracking_number alone.
CREATE UNIQUE INDEX IF NOT EXISTS shipments_tracking_uniq
  ON public.shipments (tracking_number)
  WHERE tracking_number <> '';
