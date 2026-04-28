-- 20260428110000_insight_feedback.sql
-- Rage-shake feedback channel for time-aware BioChecha insights.
-- See docs/superpowers/specs/2026-04-28-time-aware-insights-design.md.

BEGIN;

CREATE TABLE IF NOT EXISTS public.insight_feedback (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  insight_id   uuid REFERENCES public.insights(id) ON DELETE SET NULL,
  insight_body text,                  -- snapshot at feedback time
  reaction     text NOT NULL,         -- user's free text
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS insight_feedback_user_created_idx
  ON public.insight_feedback (user_id, created_at DESC);

ALTER TABLE public.insight_feedback ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS insight_feedback_select_own ON public.insight_feedback;
DROP POLICY IF EXISTS insight_feedback_insert_own ON public.insight_feedback;

CREATE POLICY insight_feedback_select_own
  ON public.insight_feedback FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY insight_feedback_insert_own
  ON public.insight_feedback FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

COMMIT;
