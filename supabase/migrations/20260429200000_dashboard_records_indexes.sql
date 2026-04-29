-- 20260429200000_dashboard_records_indexes.sql
--
-- Pre-public perf pass (Round 2). dashboard_records had no non-PK
-- indexes; every read was a seq scan. The hot queries that motivated
-- adding these:
--
-- Insight gather (biochecha_dynamic_insight.py):
--   _gather_today_meals    : (user_id, type=meal,         category=nutrition, created_at >= today)
--   _gather_today_calendar : (user_id, type=event,        category=calendar,  created_at >= today)
--   _gather_targets        : (user_id, type=progress_summary, category=nutrition) order by created_at desc limit 1
--
-- iOS Today/Orders read paths similarly group by (user_id, category, type).
--
-- Plus a GIN index on order_corrections.source_email_ids for the
-- promote_merchant_rules JOIN that uses `email_id = ANY(...)`. Today
-- the corrections set is small; this future-proofs the path.

CREATE INDEX IF NOT EXISTS dashboard_records_user_cat_type_created_idx
  ON public.dashboard_records (user_id, category, type, created_at DESC);

CREATE INDEX IF NOT EXISTS dashboard_records_user_created_idx
  ON public.dashboard_records (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS order_corrections_source_email_ids_gin
  ON public.order_corrections USING GIN (source_email_ids);
