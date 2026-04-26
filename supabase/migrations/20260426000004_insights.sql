-- ============================================================================
-- 20260426000004_insights.sql
--
-- Insights table — agents (BioChecha first; Claudinho + others later)
-- write one row per insight they generate. The iOS app reads from this
-- table to display the daily-insight card on the Today tab and any
-- additional insight surfaces over time.
--
-- Why a dedicated table (vs reusing dashboard_records):
-- * Insights have specific lifecycle (generated → shown → dismissed/pinned)
--   that doesn't map cleanly to dashboard_records' generic feed shape.
-- * Source-data references and validity windows (`valid_for_date`,
--   `expires_at`) are insight-specific concerns.
-- * Keeps the analytics surface clean — "what insights have we
--   generated this month" is a cleaner query against a focused table.
--
-- See docs/superpowers/specs/2026-04-26-insights-and-health-integrations-design.md
-- for the full architecture.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.insights (
  id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid          NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  agent_id        text          NOT NULL REFERENCES public.agents(id) ON DELETE RESTRICT,
  insight_type    text          NOT NULL CHECK (length(insight_type) > 0),
  title           text,
  body            text          NOT NULL CHECK (length(body) > 0),
  data            jsonb,
  source_refs     jsonb,
  generated_at    timestamptz   NOT NULL DEFAULT now(),
  valid_for_date  date,
  shown_at        timestamptz,
  dismissed_at    timestamptz,
  pinned          boolean       NOT NULL DEFAULT false,
  expires_at      timestamptz,
  created_at      timestamptz   NOT NULL DEFAULT now(),
  updated_at      timestamptz   NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.insights IS
  'Agent-generated insights for the Today-tab insight card and other '
  'insight surfaces. One row per insight. Lifecycle: generated → '
  'shown → dismissed/pinned. See spec: '
  '2026-04-26-insights-and-health-integrations-design.md';

COMMENT ON COLUMN public.insights.insight_type IS
  'Discriminator: ''daily_health'', ''cross_domain'', ''spending_pattern'', '
  '''anomaly'', ''negative_space'', ''latency''. iOS uses this to decide '
  'where + how to render the insight.';

COMMENT ON COLUMN public.insights.body IS
  'The writerly paragraph the agent generated. Renders as serif italic '
  'in the iOS card. Tone reference: BioChecha IDENTITY.md (data-driven, '
  'no-BS, encouraging — not preachy, not data-dumpy).';

COMMENT ON COLUMN public.insights.source_refs IS
  'Pointers back to the records that informed the insight — typed as '
  '{ "type": "health_metrics" | "records" | "orders", "ids": [...] }. '
  'Powers the "tap to see sources" expansion in the iOS card.';

COMMENT ON COLUMN public.insights.valid_for_date IS
  'For daily insights, the date the insight covers. Lets the iOS card '
  'show "today''s" insight without scanning all rows. Null for '
  'as-detected insights (anomaly, latency, etc.).';

-- iOS daily-card lookup: today's insight for this user, ordered by
-- most-recent generation if multiple agents wrote one.
CREATE INDEX IF NOT EXISTS insights_user_valid_for_date_idx
  ON public.insights (user_id, valid_for_date DESC, generated_at DESC)
  WHERE valid_for_date IS NOT NULL;

-- "Show me my pinned insights" path.
CREATE INDEX IF NOT EXISTS insights_user_pinned_idx
  ON public.insights (user_id, generated_at DESC)
  WHERE pinned = true;

-- General reverse-chronological for browsing all recent insights.
CREATE INDEX IF NOT EXISTS insights_user_recent_idx
  ON public.insights (user_id, generated_at DESC);

-- ─── RLS ──────────────────────────────────────────────────────────────────────

ALTER TABLE public.insights ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS insights_select_own ON public.insights;
DROP POLICY IF EXISTS insights_insert_own ON public.insights;
DROP POLICY IF EXISTS insights_update_own ON public.insights;
DROP POLICY IF EXISTS insights_delete_own ON public.insights;

CREATE POLICY insights_select_own ON public.insights FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY insights_insert_own ON public.insights FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY insights_update_own ON public.insights FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY insights_delete_own ON public.insights FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- ─── updated_at trigger ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.update_insights_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS insights_updated_at_trigger ON public.insights;
CREATE TRIGGER insights_updated_at_trigger
  BEFORE UPDATE ON public.insights
  FOR EACH ROW
  EXECUTE FUNCTION public.update_insights_updated_at();

COMMIT;
