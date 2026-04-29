-- 20260429520000_realtime_index_autovacuum.sql
--
-- Round-4 backend perf cleanups:
--
-- 1. `bookmarks` is in `supabase_realtime` publication but no iOS
--    subscription consumes it — every WAL insert pays the realtime
--    decoder cost for nothing. Drop from publication.
--
-- 2. `idx_learned_senders_user_id` is a redundant prefix index — the
--    UNIQUE `learned_senders_user_email_unique` on (user_id, sender_email)
--    already serves any WHERE user_id = $ lookup as a prefix scan.
--    Dropping the redundant single-column index frees write overhead.
--
-- 3. Several small high-churn tables have ~100–300% dead-tuple ratios
--    because the default autovacuum_vacuum_threshold (50) is too coarse.
--    `replaceOrderItems` does DELETE-then-INSERT; that pattern keeps
--    `order_items` in a chronic dead state. Tighter thresholds keep
--    them bloat-free.

-- ─── 1. Drop bookmarks from realtime publication ────────────────────────

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'bookmarks'
  ) THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.bookmarks;
  END IF;
END;
$$;

-- ─── 2. Drop redundant single-column index ──────────────────────────────

DROP INDEX IF EXISTS public.idx_learned_senders_user_id;

-- ─── 3. Autovacuum threshold tightening on small high-churn tables ──────

DO $$
DECLARE
  t text;
BEGIN
  FOR t IN SELECT unnest(ARRAY['order_items','insights','records','order_corrections']) LOOP
    IF EXISTS (SELECT 1 FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relname = t) THEN
      EXECUTE format(
        'ALTER TABLE public.%I SET (autovacuum_vacuum_threshold = 10, autovacuum_vacuum_scale_factor = 0.05)',
        t
      );
    END IF;
  END LOOP;
END;
$$;
