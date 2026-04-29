-- 20260429500000_critical_rls_fix.sql
--
-- CRITICAL — pre-public security fix.
--
-- Round-4 audit caught:
--   * `dashboard_records`, `home_widgets`, `sections` shipping with
--     `relrowsecurity = false` — RLS was DISABLED entirely. The
--     `dashboard_records` table had 2,338 rows of personal health data
--     readable by any anon-keyed request.
--   * `token_usage` had `Allow * for all` PERMISSIVE policies that
--     nullified its proper user-scoped policies (PERMISSIVE policies OR).
--   * The `dashboard_records` table itself was never created by any
--     committed migration — it lived only in production from a manual
--     creation. A fresh install per SETUP-FOR-AGENTS would 404 on it.
--
-- This migration:
--   1. Creates `dashboard_records` IF NOT EXISTS so fresh installs work
--      (no-op on existing production where it already exists).
--   2. Drops three legacy "Allow * for all" policies on dashboard_records
--      (predicate `true`, which would expose the whole table once RLS was
--      enabled).
--   3. Adds proper user-scoped SELECT/INSERT/UPDATE/DELETE policies that
--      match the rest of the schema (cached `(select auth.uid())` form).
--   4. Enables RLS on dashboard_records, home_widgets, and sections.
--   5. Drops the parallel stale policies on token_usage that nullified
--      its existing user-scoped policies.

-- ─── 0. Ensure dashboard_records exists for fresh installs ───────────────

CREATE TABLE IF NOT EXISTS public.dashboard_records (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id      text NOT NULL,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type          text NOT NULL,
  category      text NOT NULL,
  title         text NOT NULL,
  data          jsonb NOT NULL DEFAULT '{}'::jsonb,
  display_hint  text NOT NULL DEFAULT 'single_value',
  annotations   jsonb,
  pinned        boolean DEFAULT false,
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now(),
  expires_at    timestamptz
);

-- Recreate the indexes we know exist on the production table so a
-- fresh install matches the live shape.
CREATE INDEX IF NOT EXISTS dashboard_records_user_created_idx
  ON public.dashboard_records (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS dashboard_records_user_category_idx
  ON public.dashboard_records (user_id, category);

-- ─── 1. dashboard_records ────────────────────────────────────────────────

DROP POLICY IF EXISTS "Allow insert for all" ON public.dashboard_records;
DROP POLICY IF EXISTS "Allow read for all"   ON public.dashboard_records;
DROP POLICY IF EXISTS "Allow update for all" ON public.dashboard_records;

CREATE POLICY "dashboard_records_select_own"
  ON public.dashboard_records FOR SELECT TO authenticated
  USING (user_id = (select auth.uid()));

CREATE POLICY "dashboard_records_insert_own"
  ON public.dashboard_records FOR INSERT TO authenticated
  WITH CHECK (user_id = (select auth.uid()));

CREATE POLICY "dashboard_records_update_own"
  ON public.dashboard_records FOR UPDATE TO authenticated
  USING (user_id = (select auth.uid()))
  WITH CHECK (user_id = (select auth.uid()));

CREATE POLICY "dashboard_records_delete_own"
  ON public.dashboard_records FOR DELETE TO authenticated
  USING (user_id = (select auth.uid()));

ALTER TABLE public.dashboard_records ENABLE ROW LEVEL SECURITY;

-- ─── 2. home_widgets ─────────────────────────────────────────────────────
-- Already has `home_widgets_all_own` policy in place. Just enable RLS.

ALTER TABLE public.home_widgets ENABLE ROW LEVEL SECURITY;

-- ─── 3. sections ─────────────────────────────────────────────────────────
-- Already has `sections_all_own` policy in place. Just enable RLS.

ALTER TABLE public.sections ENABLE ROW LEVEL SECURITY;

-- ─── 4. token_usage stale wide-open policies ─────────────────────────────

DROP POLICY IF EXISTS "Allow insert for all" ON public.token_usage;
DROP POLICY IF EXISTS "Allow read for all"   ON public.token_usage;
