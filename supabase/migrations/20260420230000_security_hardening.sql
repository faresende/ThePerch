-- ============================================================================
-- 20260420_security_hardening.sql
--
-- Hardening migration written as part of the 2026-04-20 security audit. Do
-- NOT run automatically. Apply with:
--
--   supabase db push --project-ref <YOUR-PROJECT-REF>
--
-- Review the diff before applying.
--
-- What this migration does:
--   1. Enables RLS on public.dashboard_records, public.home_widgets, and
--      public.sections, which had policies defined but RLS disabled.
--   2. Replaces the permissive "Allow insert/read/update for all" policies
--      on public.dashboard_records with per-operation owner-scoped policies
--      using auth.uid() = user_id.
--   3. Drops the over-permissive "Allow insert for all" policy on
--      public.token_usage and replaces it with an authenticated,
--      owner-scoped INSERT policy.
--   4. Pins search_path on six trigger functions that the Supabase advisor
--      flagged with mutable search_path.
--
-- What this migration does NOT do:
--   * Touch auth schema tables (those are Supabase-managed).
--   * Enable Leaked Password Protection (that is a dashboard setting, noted
--     in SECURITY_AUDIT.md for manual enablement).
--
-- Ownership column verification (derived from backend/migrations/001 and
-- supabase/001_initial_schema.sql):
--   * dashboard_records.user_id  NOT NULL, FK auth.users(id)  ON DELETE CASCADE
--   * home_widgets.user_id       NOT NULL, FK public.users(id) ON DELETE CASCADE
--   * sections.user_id           NOT NULL, FK public.users(id) ON DELETE CASCADE
--   * token_usage.user_id        nullable (added in 002_users_table.sql)
-- ============================================================================

BEGIN;

-- ─── 1. dashboard_records ────────────────────────────────────────────────

ALTER TABLE public.dashboard_records ENABLE ROW LEVEL SECURITY;

-- Drop any permissive legacy policies.
DROP POLICY IF EXISTS "Allow insert for all"         ON public.dashboard_records;
DROP POLICY IF EXISTS "Allow read for all"           ON public.dashboard_records;
DROP POLICY IF EXISTS "Allow update for all"         ON public.dashboard_records;
DROP POLICY IF EXISTS "Allow insert/read/update for all" ON public.dashboard_records;

-- Drop any previously-created owner-scoped policies for idempotency.
DROP POLICY IF EXISTS dashboard_records_select_own ON public.dashboard_records;
DROP POLICY IF EXISTS dashboard_records_insert_own ON public.dashboard_records;
DROP POLICY IF EXISTS dashboard_records_update_own ON public.dashboard_records;
DROP POLICY IF EXISTS dashboard_records_delete_own ON public.dashboard_records;

CREATE POLICY dashboard_records_select_own
  ON public.dashboard_records FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY dashboard_records_insert_own
  ON public.dashboard_records FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY dashboard_records_update_own
  ON public.dashboard_records FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY dashboard_records_delete_own
  ON public.dashboard_records FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ─── 2. home_widgets ──────────────────────────────────────────────────────

ALTER TABLE public.home_widgets ENABLE ROW LEVEL SECURITY;

-- Drop prior policies (including the advisor-flagged home_widgets_all_own).
DROP POLICY IF EXISTS home_widgets_all_own    ON public.home_widgets;
DROP POLICY IF EXISTS home_widgets_select_own ON public.home_widgets;
DROP POLICY IF EXISTS home_widgets_insert_own ON public.home_widgets;
DROP POLICY IF EXISTS home_widgets_update_own ON public.home_widgets;
DROP POLICY IF EXISTS home_widgets_delete_own ON public.home_widgets;

CREATE POLICY home_widgets_select_own
  ON public.home_widgets FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY home_widgets_insert_own
  ON public.home_widgets FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY home_widgets_update_own
  ON public.home_widgets FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY home_widgets_delete_own
  ON public.home_widgets FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ─── 3. sections ──────────────────────────────────────────────────────────

ALTER TABLE public.sections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sections_all_own    ON public.sections;
DROP POLICY IF EXISTS sections_select_own ON public.sections;
DROP POLICY IF EXISTS sections_insert_own ON public.sections;
DROP POLICY IF EXISTS sections_update_own ON public.sections;
DROP POLICY IF EXISTS sections_delete_own ON public.sections;

CREATE POLICY sections_select_own
  ON public.sections FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY sections_insert_own
  ON public.sections FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY sections_update_own
  ON public.sections FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY sections_delete_own
  ON public.sections FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ─── 4. token_usage: tighten INSERT policy ────────────────────────────────

ALTER TABLE public.token_usage ENABLE ROW LEVEL SECURITY;

-- Drop the unrestricted advisor-flagged INSERT policy.
DROP POLICY IF EXISTS "Allow insert for all"  ON public.token_usage;
DROP POLICY IF EXISTS token_usage_insert_any  ON public.token_usage;

-- Replace with authenticated owner-scoped INSERT. Clients writing from the
-- app will satisfy this. Server-side workers still use the service_role key
-- (which bypasses RLS), so this does not change the agent-write path.
DROP POLICY IF EXISTS token_usage_insert_own ON public.token_usage;

CREATE POLICY token_usage_insert_own
  ON public.token_usage FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Sanity: keep the matching SELECT/UPDATE/DELETE policies defined in
-- supabase/migrations/001_enable_rls.sql intact. Re-create them defensively
-- so this migration is self-contained even if 001_enable_rls.sql was never
-- applied on this project.
DROP POLICY IF EXISTS token_usage_select_own ON public.token_usage;
CREATE POLICY token_usage_select_own
  ON public.token_usage FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS token_usage_update_own ON public.token_usage;
CREATE POLICY token_usage_update_own
  ON public.token_usage FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS token_usage_delete_own ON public.token_usage;
CREATE POLICY token_usage_delete_own
  ON public.token_usage FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ─── 5. Fix mutable search_path on advisor-flagged functions ──────────────
--
-- Attaching SET search_path via ALTER FUNCTION is the least-invasive fix; it
-- does not change function bodies. `pg_temp` is included so transient temp
-- schema names cannot be hijacked.

ALTER FUNCTION public.set_updated_at()                  SET search_path = public, pg_temp;
ALTER FUNCTION public.update_records_updated_at()       SET search_path = public, pg_temp;
ALTER FUNCTION public.update_orders_updated_at()        SET search_path = public, pg_temp;
ALTER FUNCTION public.update_shipments_updated_at()     SET search_path = public, pg_temp;
ALTER FUNCTION public.update_review_items_updated_at()  SET search_path = public, pg_temp;
ALTER FUNCTION public.update_food_memories_updated_at() SET search_path = public, pg_temp;

COMMIT;

-- ─── Post-migration dashboard steps (manual) ──────────────────────────────
-- 1. Authentication → Settings → enable "Leaked Password Protection"
--    (HaveIBeenPwned integration). Not expressible in SQL.
-- 2. Authentication → Providers → review enabled providers and their
--    redirect URLs.
-- 3. Run the security advisor again to confirm all WARNings resolved:
--    Dashboard → Advisors → Security.
