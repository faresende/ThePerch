-- 20260429440000_more_fk_indexes.sql
--
-- Round-3 advisor follow-up: 8 more foreign keys without covering indexes
-- surfaced by the Supabase performance linter. Each column was already
-- joinable, just paying a sequential scan on every JOIN. Mirrors the
-- pattern established in 20260429420000_index_perf_pass.sql.

CREATE INDEX IF NOT EXISTS idx_bookmarks_record_id
  ON public.bookmarks(record_id);

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
