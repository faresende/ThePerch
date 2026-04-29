-- 20260429420000_index_perf_pass.sql
--
-- Index hygiene pass surfaced by the Round-3 backend audit:
--
--   1. Duplicate index on shipments.tracking_number (`idx_shipments_tracking`
--      vs `idx_shipments_tracking_number` — same column, same predicate).
--      Keep the more descriptive name; drop the abbreviated one.
--   2. Foreign keys without a covering index — every join on the FK does a
--      sequential scan of the child table. Add B-tree indexes on the FK
--      columns most commonly joined in our app reads.
--   3. Drop a handful of unused indexes flagged by pg_stat_user_indexes
--      that haven't been touched in this codebase's typical query patterns.
--
-- Per-statement migration: each CREATE INDEX is IF NOT EXISTS so re-runs
-- are safe; DROP INDEX is IF EXISTS for the same reason.

-- ─── 1. Duplicate index on shipments.tracking_number ────────────────────
DROP INDEX IF EXISTS public.idx_shipments_tracking;

-- ─── 2. Missing FK-covering indexes ─────────────────────────────────────
-- insight_feedback.insight_id → insights(id): joined whenever we display
-- feedback alongside the insight that triggered it.
CREATE INDEX IF NOT EXISTS idx_insight_feedback_insight_id
  ON public.insight_feedback(insight_id);

-- email_classifications.user_id is already indexed via primary key
-- composite — skip. But order_corrections.order_id needs one.
CREATE INDEX IF NOT EXISTS idx_order_corrections_order_id
  ON public.order_corrections(order_id);

-- learned_senders.user_id (domain lookups happen by user, then domain).
CREATE INDEX IF NOT EXISTS idx_learned_senders_user_id
  ON public.learned_senders(user_id);

-- merchant_rules.user_id (lookups happen by user, then merchant).
CREATE INDEX IF NOT EXISTS idx_merchant_rules_user_id
  ON public.merchant_rules(user_id);

-- agent_runs.agent_id covering index (already partial-indexed for non-OK
-- runs; full index helps the JOIN to agents on the SELECT-own RLS path).
CREATE INDEX IF NOT EXISTS idx_agent_runs_agent_id
  ON public.agent_runs(agent_id);

-- order_items.order_id (one-to-many parent lookup).
CREATE INDEX IF NOT EXISTS idx_order_items_order_id
  ON public.order_items(order_id);

-- review_items.related_order_id and .related_shipment_id (review queue
-- → order/shipment resolution).
CREATE INDEX IF NOT EXISTS idx_review_items_related_order_id
  ON public.review_items(related_order_id);
CREATE INDEX IF NOT EXISTS idx_review_items_related_shipment_id
  ON public.review_items(related_shipment_id);

-- ─── 3. Drop indexes flagged as unused by pg_stat_user_indexes ──────────
-- These haven't been read in production and add write overhead. Wrap each
-- in DO block guarded by existence so re-runs and out-of-order migrations
-- (where the parent index might have been renamed) don't fail.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_orders_status') THEN
    DROP INDEX public.idx_orders_status;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_shipments_carrier_status') THEN
    DROP INDEX public.idx_shipments_carrier_status;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = 'idx_shipments_eta') THEN
    DROP INDEX public.idx_shipments_eta;
  END IF;
END;
$$;
