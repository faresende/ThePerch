-- 20260429400000_rls_auth_uid_caching.sql
--
-- Per-row RLS evaluation kills query performance on tables with many rows
-- per user (dashboard_records, insights, health_metrics, etc.). Postgres'
-- query planner can cache the result of a scalar subquery once per
-- statement, but only if the predicate uses `(select auth.uid())` — bare
-- `auth.uid()` is treated as VOLATILE and re-evaluated per row.
--
-- This migration rewrites every existing RLS policy whose predicate
-- references `auth.uid()` (without an enclosing subquery) so it uses the
-- cached form. The rewrite is performed dynamically via pg_policies to
-- avoid drift across the historical migration files; any policy added by
-- a future migration that uses bare `auth.uid()` will be picked up if you
-- re-run the same DO block.
--
-- Reference: https://supabase.com/docs/guides/database/postgres/row-level-security#use-select-auth-uid

DO $$
DECLARE
  pol RECORD;
  new_qual TEXT;
  new_check TEXT;
  cmd_clause TEXT;
  using_clause TEXT;
  check_clause TEXT;
  roles_clause TEXT;
BEGIN
  FOR pol IN
    SELECT
      schemaname,
      tablename,
      policyname,
      permissive,
      roles,
      cmd,
      qual,
      with_check
    FROM pg_policies
    WHERE schemaname = 'public'
      AND (
        (qual LIKE '%auth.uid()%' AND qual NOT LIKE '%( SELECT auth.uid()%' AND qual NOT LIKE '%(select auth.uid()%')
        OR
        (with_check LIKE '%auth.uid()%' AND with_check NOT LIKE '%( SELECT auth.uid()%' AND with_check NOT LIKE '%(select auth.uid()%')
      )
  LOOP
    -- Wrap every bare auth.uid() in (select auth.uid()).
    -- Negative lookbehind isn't available in POSIX regexp_replace, so we
    -- first guard against double-wrapping by checking the prefix above,
    -- then do a straight replace here.
    new_qual := regexp_replace(pol.qual, 'auth\.uid\(\)', '(select auth.uid())', 'g');
    new_check := regexp_replace(pol.with_check, 'auth\.uid\(\)', '(select auth.uid())', 'g');

    -- Build CREATE POLICY clauses. cmd is one of SELECT, INSERT, UPDATE,
    -- DELETE, ALL — passthrough verbatim.
    cmd_clause := 'FOR ' || pol.cmd;

    -- Roles array → comma-joined identifiers.
    roles_clause := 'TO ' || array_to_string(pol.roles, ', ');

    using_clause := CASE WHEN new_qual IS NOT NULL THEN ' USING (' || new_qual || ')' ELSE '' END;
    check_clause := CASE WHEN new_check IS NOT NULL THEN ' WITH CHECK (' || new_check || ')' ELSE '' END;

    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I',
                   pol.policyname, pol.schemaname, pol.tablename);
    EXECUTE format('CREATE POLICY %I ON %I.%I AS %s %s %s%s%s',
                   pol.policyname,
                   pol.schemaname,
                   pol.tablename,
                   CASE WHEN pol.permissive = 'PERMISSIVE' THEN 'PERMISSIVE' ELSE 'RESTRICTIVE' END,
                   cmd_clause,
                   roles_clause,
                   using_clause,
                   check_clause);

    RAISE NOTICE 'rewrote policy %.%.%', pol.schemaname, pol.tablename, pol.policyname;
  END LOOP;
END;
$$;
