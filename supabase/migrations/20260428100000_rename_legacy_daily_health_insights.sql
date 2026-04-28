-- 20260428100000_rename_legacy_daily_health_insights.sql
-- Time-aware insights migration: renames legacy daily_health → daily_health_morning.
-- See docs/superpowers/specs/2026-04-28-time-aware-insights-design.md.
--
-- Already applied to production via PostgREST PATCH on 2026-04-28; this file
-- exists for replay/posterity in fresh environments.

UPDATE public.insights
SET insight_type = 'daily_health_morning'
WHERE insight_type = 'daily_health'
  AND agent_id = 'biochecha';
