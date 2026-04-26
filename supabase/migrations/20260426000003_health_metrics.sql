-- ============================================================================
-- 20260426000003_health_metrics.sql
--
-- Single canonical table for sleep + body-composition + cardiovascular
-- metrics from any source. Withings, 8sleep, manual entry, future
-- HealthKit sync — all write the same shape into the same table so
-- BioChecha (the daily-insight agent) can read uniformly without
-- caring which device the data came from.
--
-- Schema choices
-- --------------
-- * `metric` is a free text key (e.g. "sleep_duration_min", "hrv_rmssd_ms",
--   "weight_kg") rather than an enum, so adding a new metric type doesn't
--   require a migration. Drift between callers is the trade-off; we accept
--   it because the consumer (BioChecha) can normalise and the writers are
--   all in this repo.
-- * `source_id` lets us deduplicate when the same Withings measurement
--   syncs twice. UNIQUE (user_id, source, source_id, metric) is the
--   idempotency key.
-- * `details` jsonb carries source-specific extras (sleep stages,
--   deep/light minutes, raw sample arrays) that don't fit the single
--   numeric `value`.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.health_metrics (
  id            uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid          NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  metric        text          NOT NULL CHECK (length(metric) > 0),
  value         numeric       NOT NULL,
  unit          text,
  source        text          NOT NULL CHECK (length(source) > 0),
  source_id     text,
  measured_at   timestamptz   NOT NULL,
  ingested_at   timestamptz   NOT NULL DEFAULT now(),
  details       jsonb
);

COMMENT ON TABLE public.health_metrics IS
  'Canonical health metrics table — sleep, body comp, cardio. Written '
  'by ingestion scripts (8sleep / Withings / manual). Read by BioChecha '
  'to generate daily insights. Source-agnostic shape so consumers don''t '
  'care which device produced the data.';

COMMENT ON COLUMN public.health_metrics.metric IS
  'Free-text key (sleep_duration_min, hrv_rmssd_ms, weight_kg, etc.). '
  'Adding new metric types is a writer change, not a schema change.';

COMMENT ON COLUMN public.health_metrics.source_id IS
  'Vendor''s record id. Combined with (user_id, source, metric) forms '
  'the idempotency key — re-running an ingest never duplicates.';

-- Idempotent ingestion: same (user, source, source_id, metric) collapses to one row.
CREATE UNIQUE INDEX IF NOT EXISTS health_metrics_dedup_idx
  ON public.health_metrics (user_id, source, source_id, metric)
  WHERE source_id IS NOT NULL;

-- "Last 7 days of sleep" / "weight trend" queries.
CREATE INDEX IF NOT EXISTS health_metrics_user_metric_time_idx
  ON public.health_metrics (user_id, metric, measured_at DESC);

-- "Show me everything that happened on day X" cross-metric pull.
CREATE INDEX IF NOT EXISTS health_metrics_user_time_idx
  ON public.health_metrics (user_id, measured_at DESC);

-- ─── RLS ──────────────────────────────────────────────────────────────────────

ALTER TABLE public.health_metrics ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS health_metrics_select_own ON public.health_metrics;
DROP POLICY IF EXISTS health_metrics_insert_own ON public.health_metrics;
DROP POLICY IF EXISTS health_metrics_update_own ON public.health_metrics;
DROP POLICY IF EXISTS health_metrics_delete_own ON public.health_metrics;

CREATE POLICY health_metrics_select_own ON public.health_metrics FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY health_metrics_insert_own ON public.health_metrics FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY health_metrics_update_own ON public.health_metrics FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY health_metrics_delete_own ON public.health_metrics FOR DELETE TO authenticated USING (auth.uid() = user_id);

COMMIT;
