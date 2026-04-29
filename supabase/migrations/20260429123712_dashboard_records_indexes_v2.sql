-- 20260429123712_dashboard_records_indexes_v2.sql
--
-- Stub committed in Round 11 to match the prod migration ledger.
-- Idempotent (CREATE INDEX IF NOT EXISTS).

CREATE INDEX IF NOT EXISTS dashboard_records_user_cat_type_created_idx
  ON public.dashboard_records (user_id, category, type, created_at DESC);

CREATE INDEX IF NOT EXISTS dashboard_records_user_created_idx
  ON public.dashboard_records (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS order_corrections_source_email_ids_gin
  ON public.order_corrections USING GIN (source_email_ids);
