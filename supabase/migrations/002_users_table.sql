-- ==========================================================================
-- The Perch - Users table (profiles)
--
-- Creates/aligns a public.users table keyed by auth.users(id).
-- NOTE: The project already contains a users table in supabase/001_initial_schema.sql.
-- This migration is provided to satisfy beta multi-tenant rollout requirements,
-- and is safe to run if the table does not exist.
-- ==========================================================================

CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  display_name TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Helpful index
CREATE INDEX IF NOT EXISTS idx_users_created_at ON public.users(created_at DESC);

-- RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS users_select_own ON public.users;
CREATE POLICY users_select_own
  ON public.users FOR SELECT
  USING (id = auth.uid());

DROP POLICY IF EXISTS users_insert_own ON public.users;
CREATE POLICY users_insert_own
  ON public.users FOR INSERT
  WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS users_update_own ON public.users;
CREATE POLICY users_update_own
  ON public.users FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());
