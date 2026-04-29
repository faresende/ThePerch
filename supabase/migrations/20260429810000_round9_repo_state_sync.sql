-- 20260429810000_round9_repo_state_sync.sql
--
-- Round 9 audit caught a "verify the fix landed" gap: several DDL changes
-- were applied directly to prod via the Supabase dashboard / MCP and never
-- committed as repo migrations. A fresh-install user (forking the repo +
-- running the migrations sequence in SETUP-FOR-AGENTS Step 4) would end
-- up missing security-relevant state. This migration consolidates the
-- pieces so the repo is the source of truth.
--
-- Pieces brought in here:
--   1. idle_in_transaction_session_timeout = 60s at the DATABASE level +
--      authenticator (login) role. R7 set this on `authenticated`/`anon`
--      which are nologin roles, so it was a no-op. R8 fixed it in prod
--      via dashboard, but never committed the migration.
--   2. public.bookmarks table + RLS policies + indexes + triggers.
--      The Safari extension (POST /rest/v1/bookmarks) and iOS Hub bookmarks
--      flow both reference this table; without it, fresh installs see
--      404s and the Safari extension's only action errors.
--   3. rls_auto_enable() event trigger function + ensure_rls event trigger.
--      Defense-in-depth safeguard that auto-enables RLS on every new
--      public-schema table. If a future migration ever forgets to
--      `ENABLE ROW LEVEL SECURITY` on a CREATE TABLE, this catches it.

BEGIN;

-- ─── 1. idle_in_transaction_session_timeout — DATABASE + login role ────
-- ALTER DATABASE applies to every connection (login). The authenticator
-- ALTER ROLE is defense-in-depth: Postgres applies role-level GUCs at
-- LOGIN, and authenticator is the actual login role PostgREST uses.
ALTER DATABASE postgres   SET idle_in_transaction_session_timeout = '60s';
ALTER ROLE     authenticator SET idle_in_transaction_session_timeout = '60s';

-- ─── 2. public.bookmarks table ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.bookmarks (
  id                    uuid           PRIMARY KEY DEFAULT gen_random_uuid(),
  record_id             uuid           REFERENCES public.records(id) ON DELETE CASCADE,
  user_id               uuid           NOT NULL    REFERENCES public.users(id) ON DELETE CASCADE,
  url                   text           NOT NULL,
  domain                text,
  original_title        text,
  enriched_title        text,
  summary               text,
  tags                  text[]                     DEFAULT '{}'::text[],
  status                text           NOT NULL    DEFAULT 'pending',
  image_url             text,
  reading_time_minutes  integer,
  submitted_from        text,
  processed_at          timestamptz,
  created_at            timestamptz                DEFAULT now(),
  updated_at            timestamptz                DEFAULT now(),
  fts                   tsvector,
  CONSTRAINT bookmarks_status_check
    CHECK (status = ANY (ARRAY['pending', 'processing', 'processed', 'failed'])),
  CONSTRAINT bookmarks_submitted_from_check
    CHECK (submitted_from IS NULL
       OR  submitted_from = ANY (ARRAY['ios_share', 'safari_extension', 'telegram', 'webchat']))
);

CREATE INDEX IF NOT EXISTS idx_bookmarks_record_id    ON public.bookmarks (record_id);
CREATE INDEX IF NOT EXISTS idx_bookmarks_user_created ON public.bookmarks (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookmarks_domain       ON public.bookmarks (user_id, domain);
CREATE INDEX IF NOT EXISTS idx_bookmarks_tags         ON public.bookmarks USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_bookmarks_fts          ON public.bookmarks USING GIN (fts);

ALTER TABLE public.bookmarks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS bookmarks_read_own   ON public.bookmarks;
DROP POLICY IF EXISTS bookmarks_insert_own ON public.bookmarks;
DROP POLICY IF EXISTS bookmarks_update_own ON public.bookmarks;
DROP POLICY IF EXISTS bookmarks_delete_own ON public.bookmarks;

CREATE POLICY bookmarks_read_own
  ON public.bookmarks FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY bookmarks_insert_own
  ON public.bookmarks FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY bookmarks_update_own
  ON public.bookmarks FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY bookmarks_delete_own
  ON public.bookmarks FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- updated_at touch on UPDATE — reuses the records helper.
DROP TRIGGER IF EXISTS trigger_bookmarks_updated_at ON public.bookmarks;
CREATE TRIGGER trigger_bookmarks_updated_at
  BEFORE UPDATE ON public.bookmarks
  FOR EACH ROW
  EXECUTE FUNCTION public.update_records_updated_at();

-- ─── 3. rls_auto_enable() event trigger function ────────────────────────
-- Watches CREATE TABLE / CTAS / SELECT INTO and forces RLS on for any new
-- public-schema table. Logs (RAISE LOG) on success/failure — never
-- aborts the parent DDL. Defense-in-depth guard: anon has GRANT ALL on
-- every public table, so RLS is the only gate against cross-tenant reads.
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
  RETURNS event_trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = pg_catalog
AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table', 'partitioned table')
  LOOP
    IF cmd.schema_name IS NOT NULL
       AND cmd.schema_name IN ('public')
       AND cmd.schema_name NOT IN ('pg_catalog', 'information_schema')
       AND cmd.schema_name NOT LIKE 'pg_toast%'
       AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
    ELSE
      RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)',
        cmd.object_identity, cmd.schema_name;
    END IF;
  END LOOP;
END;
$$;

DROP EVENT TRIGGER IF EXISTS ensure_rls;
CREATE EVENT TRIGGER ensure_rls
  ON ddl_command_end
  WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  EXECUTE FUNCTION public.rls_auto_enable();

COMMENT ON FUNCTION public.rls_auto_enable() IS
  'Round 9: defense-in-depth. Auto-enables RLS on any new public-schema table created via CREATE TABLE / CTAS / SELECT INTO. Failures are logged, never propagated.';

-- ─── 4. prune_email_classifications: 7-day floor guard ─────────────────
-- prune_agent_runs already has this guard. prune_email_classifications
-- accepts any integer including 0 and negatives; with service-role
-- compromise that's a one-call wipe of all email-classification history.
-- Mirror the same defense.
CREATE OR REPLACE FUNCTION public.prune_email_classifications(days integer DEFAULT 90)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted integer;
BEGIN
  IF days < 7 THEN
    RAISE EXCEPTION 'prune_email_classifications: refuse to prune anything younger than 7 days (got %)', days;
  END IF;
  DELETE FROM public.email_classifications
  WHERE classified_at < (now() - (days || ' days')::interval);

  GET DIAGNOSTICS deleted = ROW_COUNT;
  RETURN deleted;
END;
$$;

-- Lock-down (idempotent — safe to re-run).
REVOKE ALL ON FUNCTION public.prune_email_classifications(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.prune_email_classifications(integer) FROM authenticated;
REVOKE ALL ON FUNCTION public.prune_email_classifications(integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.prune_email_classifications(integer) TO service_role;

COMMIT;
