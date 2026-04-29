-- 20260429440000_more_fk_indexes.sql
--
-- Round-3 advisor follow-up: 8 more foreign keys without covering indexes
-- surfaced by the Supabase performance linter. Each column was already
-- joinable, just paying a sequential scan on every JOIN. Mirrors the
-- pattern established in 20260429420000_index_perf_pass.sql.

-- public.bookmarks is a legacy table that exists in production from a
-- pre-public manual creation but is never created by any committed
-- migration (Round 5 dropped its unused FK index; Round 6 docs audit
-- caught that the original index-create line breaks fresh installs).
-- Guard the create so a fresh install doesn't fail. If/when bookmarks
-- gets a CREATE TABLE migration, the guard becomes a no-op.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class
    WHERE relnamespace = 'public'::regnamespace
      AND relname = 'bookmarks'
      AND relkind = 'r'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_bookmarks_record_id
      ON public.bookmarks(record_id);
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_dashboard_records_agent_id
  ON public.dashboard_records(agent_id);

CREATE INDEX IF NOT EXISTS idx_email_classifications_related_order_id
  ON public.email_classifications(related_order_id);

CREATE INDEX IF NOT EXISTS idx_email_classifications_related_review_item_id
  ON public.email_classifications(related_review_item_id);

CREATE INDEX IF NOT EXISTS idx_food_memories_reference_meal_record_id
  ON public.food_memories(reference_meal_record_id);

CREATE INDEX IF NOT EXISTS idx_insights_agent_id
  ON public.insights(agent_id);

CREATE INDEX IF NOT EXISTS idx_learned_senders_learned_from_review_item_id
  ON public.learned_senders(learned_from_review_item_id);

CREATE INDEX IF NOT EXISTS idx_token_usage_agent_id
  ON public.token_usage(agent_id);
