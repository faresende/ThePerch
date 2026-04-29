-- 20260429180159_round10_drop_bookmarks_fts_dead_code.sql
--
-- Stub committed in Round 11 to match the prod migration ledger.
-- Round 10: dropped dead `bookmarks.fts tsvector` column +
-- idx_bookmarks_fts GIN index. The column had no populator and no
-- consumer in iOS / Safari extension. Also REVOKE bookmarks from
-- anon — defense-in-depth.
--
-- Note: 20260429810000_round9_repo_state_sync.sql already creates
-- `bookmarks` WITHOUT the fts column and WITH the anon REVOKE, so
-- on a fresh install this migration's statements are pure no-ops.
-- Kept here so the ledger versions match prod.

DROP INDEX IF EXISTS public.idx_bookmarks_fts;
ALTER TABLE public.bookmarks DROP COLUMN IF EXISTS fts;
REVOKE ALL ON TABLE public.bookmarks FROM anon;
