-- 20260429410000_realtime_publication_fix.sql
--
-- supabase_realtime publication misconfiguration: the initial schema added
-- `public.records` (the legacy pre-dashboard_records table that no longer
-- backs any product feature) but iOS subscribes to `public.dashboard_records`.
-- That mismatch silently disables realtime for the canonical card feed —
-- iOS never receives insert/update/delete events for new measurements,
-- bookmarks, calendar events, etc., and falls back to manual refresh.
--
-- This migration drops the legacy table from the publication and adds the
-- canonical one, plus sets REPLICA IDENTITY FULL on dashboard_records and
-- agents so realtime payloads include the full pre-update row (needed for
-- our merge logic in iOS DashboardViewModel).

-- 1. Drop legacy table from publication if present (no-op if not).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'records'
  ) THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.records;
  END IF;
END;
$$;

-- 2. Add canonical table to publication if not present.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'dashboard_records'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.dashboard_records;
  END IF;
END;
$$;

-- 3. Ensure agents stays in the publication (was added in 001).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'agents'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.agents;
  END IF;
END;
$$;

-- 4. REPLICA IDENTITY FULL so DELETE / UPDATE payloads carry the full row.
-- Without this, only the primary key columns appear in the change record,
-- which breaks the iOS merge logic that diffs by `(id, updated_at)`.
ALTER TABLE public.dashboard_records REPLICA IDENTITY FULL;
ALTER TABLE public.agents REPLICA IDENTITY FULL;
