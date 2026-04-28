-- 20260428120000_register_calendar_sync_agent.sql
-- Registers the calendar-sync agent so its dashboard_records rows
-- (category='calendar', type='event') satisfy the
-- dashboard_records_agent_id_fkey foreign key.
--
-- The agent is the macOS-only calendar_sync.py worker that runs
-- every 15 minutes during waking hours and feeds today's Calendar.app
-- events into dashboard_records for BioChecha's time-aware insights.

INSERT INTO public.agents (id, display_name, emoji, model, is_active, owner_id)
VALUES (
  'calendar-sync',
  'Calendar Sync',
  '📆',
  'python:calendar-sync',
  true,
  '00000000-0000-0000-0000-000000000000'
)
ON CONFLICT (id) DO NOTHING;
