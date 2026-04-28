-- ============================================================================
-- 20260428000000_health_metrics_full_unique_constraint.sql
--
-- Replace the partial unique index (health_metrics_dedup_idx) with a
-- full UNIQUE constraint so PostgREST's on_conflict upsert path can
-- match it. The previous partial form (`WHERE source_id IS NOT NULL`)
-- can't be referenced by ON CONFLICT without the WHERE clause, which
-- PostgREST's URL-parameter-only on_conflict syntax can't express.
--
-- Caught when re-ingesting metrics on a second day: every row hit
-- 23505 duplicate-key error because PostgREST's on_conflict fell back
-- to the primary key (auto-generated UUID, never duplicated), bypassing
-- the natural-key dedup path.
--
-- Functional equivalence: PG UNIQUE constraints treat NULLs as
-- distinct by default, so rows with NULL source_id are allowed in
-- multiples — same as before.
-- ============================================================================

BEGIN;

DROP INDEX IF EXISTS public.health_metrics_dedup_idx;

ALTER TABLE public.health_metrics
  ADD CONSTRAINT health_metrics_dedup_uniq
  UNIQUE (user_id, source, source_id, metric);

COMMENT ON CONSTRAINT health_metrics_dedup_uniq ON public.health_metrics IS
  'Idempotent dedup: (user_id, source, source_id, metric) tuple is the natural key for ingested metrics. Replaces partial unique index health_metrics_dedup_idx so PostgREST upsert (on_conflict=...) can match. NULLs treated as distinct, preserving prior semantics.';

COMMIT;
