-- 20260429600000_round5_index_policy_cleanup.sql
--
-- Round-5 backend cleanup, all flagged by `pg_stat_user_indexes` /
-- `pg_policies` advisor:
--
-- 1. Add an unconditional `dashboard_records (created_at DESC)` index
--    so the iOS catalog query (`SELECT * ORDER BY created_at DESC LIMIT N`)
--    stops paying the seq-scan + top-N heapsort. RLS adds a runtime
--    `user_id = auth.uid()` filter but the planner can't push it into
--    a WHERE, so the existing user-prefixed index is unusable.
-- 2. Drop the redundant non-unique `idx_shipments_tracking_number` —
--    the unique `(order_id, tracking_number)` composite already covers
--    every lookup pattern this app does.
-- 3. Drop a list of indexes pg_stat_user_indexes reports as unused.
--    They cost write overhead on every INSERT/UPDATE for no benefit.
-- 4. Tighten autovacuum on shipments / orders / agent_runs /
--    email_classifications (Round 4 did insights/order_items/records/
--    order_corrections only).
-- 5. Drop 5 duplicate-permissive RLS policies.
-- 6. REPLICA IDENTITY DEFAULT for dashboard_records + agents (was FULL,
--    doubled WAL volume on every UPDATE for no iOS benefit).

-- ─── 1. dashboard_records catalog-query index ───────────────────────────

CREATE INDEX IF NOT EXISTS idx_dashboard_records_created_at_desc
  ON public.dashboard_records (created_at DESC);

-- ─── 2. Redundant non-unique index ──────────────────────────────────────

DROP INDEX IF EXISTS public.idx_shipments_tracking_number;

-- ─── 3. Drop unused indexes ─────────────────────────────────────────────
-- Each is wrapped in DO block so re-runs / drift don't fail.

DO $$
DECLARE
  ix text;
BEGIN
  FOR ix IN SELECT unnest(ARRAY[
    'idx_orders_manual_delivered',
    'idx_orders_order_date',
    'idx_shipments_status',
    'idx_shipments_order_id',
    'idx_agent_users_user_id',
    'idx_users_created_at',
    'idx_agents_owner_id',
    'idx_agents_created_at',
    'idx_records_agent_id',
    'idx_records_user_id_pinned',
    'idx_records_state',
    'idx_home_widgets_user_id_sort',
    'dashboard_records_user_category_idx',
    'idx_token_usage_user_id_date',
    'idx_email_classifications_related_order_id',
    'idx_email_classifications_related_review_item_id',
    'idx_food_memories_user_id',
    'idx_food_memory_observations_user_id',
    'idx_bookmarks_user_id',
    'idx_bookmarks_created_at',
    'idx_bookmarks_status',
    'email_classifications_user_recent_idx',
    'email_classifications_user_sender_idx',
    'idx_insights_agent_id',
    'idx_learned_senders_learned_from_review_item_id',
    'idx_insight_feedback_insight_id',
    'idx_order_corrections_order_id',
    'order_corrections_source_email_ids_gin',
    'idx_merchant_rules_user_id',
    'idx_agent_runs_agent_id',
    'idx_order_items_order_id',
    'idx_review_items_related_order_id',
    'idx_review_items_related_shipment_id',
    'agent_runs_non_ok_idx',
    'insights_user_pinned_idx'
  ]) LOOP
    IF EXISTS (
      SELECT 1 FROM pg_indexes
      WHERE schemaname = 'public' AND indexname = ix
    ) THEN
      EXECUTE format('DROP INDEX public.%I', ix);
    END IF;
  END LOOP;
END;
$$;

-- ─── 4. Autovacuum tightening (additional tables) ───────────────────────

DO $$
DECLARE
  t text;
BEGIN
  FOR t IN SELECT unnest(ARRAY['shipments','orders','agent_runs','email_classifications']) LOOP
    IF EXISTS (SELECT 1 FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relname = t) THEN
      EXECUTE format(
        'ALTER TABLE public.%I SET (autovacuum_vacuum_threshold = 10, autovacuum_vacuum_scale_factor = 0.05)',
        t
      );
    END IF;
  END LOOP;
END;
$$;

-- ─── 5. Drop duplicate / shadowed RLS policies ──────────────────────────

DROP POLICY IF EXISTS records_select_own       ON public.records;        -- subset of records_read_own
DROP POLICY IF EXISTS records_insert_agent_owner ON public.records;      -- now-redundant after Round 4 tightened user_id check
DROP POLICY IF EXISTS agents_select_own        ON public.agents;         -- subset of agents_read_accessible
DROP POLICY IF EXISTS users_select_own         ON public.users;          -- duplicate of users_read_own
DROP POLICY IF EXISTS agent_users_read_own     ON public.agent_users;    -- shadowed by agent_users_manage_by_owner

-- ─── 6. REPLICA IDENTITY DEFAULT (idempotent — Round 5 already applied) ─

ALTER TABLE public.dashboard_records REPLICA IDENTITY DEFAULT;
ALTER TABLE public.agents             REPLICA IDENTITY DEFAULT;
