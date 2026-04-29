-- ============================================================================
-- The Perch - Initial Database Schema Migration
-- ============================================================================
-- This migration sets up the core tables, indexes, RLS policies, and
-- realtime subscriptions for The Perch project.
-- ============================================================================

-- ============================================================================
-- 1. USERS TABLE (extends auth.users)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  preferences JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_created_at ON public.users(created_at DESC);

-- ============================================================================
-- 2. AGENTS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.agents (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  emoji TEXT,
  model TEXT,
  is_active BOOLEAN DEFAULT true,
  last_heartbeat TIMESTAMPTZ,
  owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_agents_owner_id ON public.agents(owner_id);
CREATE INDEX IF NOT EXISTS idx_agents_created_at ON public.agents(created_at DESC);

-- ============================================================================
-- 3. AGENT_USERS MAPPING TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.agent_users (
  agent_id TEXT NOT NULL REFERENCES public.agents(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'viewer',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (agent_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_agent_users_user_id ON public.agent_users(user_id);

-- ============================================================================
-- 4. RECORDS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id TEXT NOT NULL REFERENCES public.agents(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  category TEXT NOT NULL,
  title TEXT NOT NULL,
  data JSONB NOT NULL DEFAULT '{}',
  display_hint TEXT NOT NULL,
  annotations JSONB DEFAULT '{}',
  pinned BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  CHECK (length(title) > 0),
  CHECK (length(display_hint) > 0)
);

CREATE INDEX IF NOT EXISTS idx_records_user_id_category ON public.records(user_id, category);
CREATE INDEX IF NOT EXISTS idx_records_agent_id ON public.records(agent_id);
CREATE INDEX IF NOT EXISTS idx_records_type ON public.records(type);
CREATE INDEX IF NOT EXISTS idx_records_created_at ON public.records(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_records_user_id_pinned ON public.records(user_id, pinned) WHERE pinned = true;

-- ============================================================================
-- 4b. DASHBOARD_RECORDS TABLE (canonical card feed for the iOS app)
-- ============================================================================
-- `dashboard_records` superseded `records` early in the project's life
-- but the schema migration that introduced it never landed in the
-- committed history. Production has the table from a manual creation;
-- a fresh install needs it before any later migration touches it
-- (security_hardening, dashboard_records_indexes, realtime_publication_fix,
-- more_fk_indexes all reference public.dashboard_records).

CREATE TABLE IF NOT EXISTS public.dashboard_records (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id      TEXT NOT NULL,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type          TEXT NOT NULL,
  category      TEXT NOT NULL,
  title         TEXT NOT NULL,
  data          JSONB NOT NULL DEFAULT '{}'::jsonb,
  display_hint  TEXT NOT NULL DEFAULT 'card',
  annotations   JSONB,
  pinned        BOOLEAN DEFAULT false,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW(),
  expires_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS dashboard_records_user_created_idx
  ON public.dashboard_records (user_id, created_at DESC);

-- ============================================================================
-- 5. TOKEN_USAGE TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.token_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id TEXT NOT NULL REFERENCES public.agents(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  input_tokens INT DEFAULT 0,
  output_tokens INT DEFAULT 0,
  model TEXT,
  estimated_cost_usd NUMERIC(10, 4) DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (agent_id, date, model)
);

CREATE INDEX IF NOT EXISTS idx_token_usage_agent_id_date ON public.token_usage(agent_id, date);

-- ============================================================================
-- 6. SECTIONS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.sections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  slug TEXT NOT NULL,
  display_name TEXT NOT NULL,
  sort_order INT DEFAULT 0,
  is_visible BOOLEAN DEFAULT true,
  config JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, slug),
  CHECK (length(slug) > 0),
  CHECK (length(display_name) > 0)
);

CREATE INDEX IF NOT EXISTS idx_sections_user_id_sort ON public.sections(user_id, sort_order);

-- ============================================================================
-- 7. HOME_WIDGETS TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.home_widgets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  widget_type TEXT NOT NULL,
  config JSONB NOT NULL DEFAULT '{}',
  sort_order INT DEFAULT 0,
  size TEXT DEFAULT 'medium',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CHECK (size IN ('small', 'medium', 'large')),
  CHECK (length(widget_type) > 0)
);

CREATE INDEX IF NOT EXISTS idx_home_widgets_user_id_sort ON public.home_widgets(user_id, sort_order);

-- ============================================================================
-- 8. TRIGGER: Auto-update updated_at on records
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_records_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_records_updated_at ON public.records;
CREATE TRIGGER trigger_records_updated_at
BEFORE UPDATE ON public.records
FOR EACH ROW
EXECUTE FUNCTION public.update_records_updated_at();

-- ============================================================================
-- 9. ENABLE ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.token_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.home_widgets ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 10. RLS POLICIES: USERS
-- ============================================================================

-- Users can read their own profile
CREATE POLICY users_read_own
  ON public.users FOR SELECT
  USING (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY users_update_own
  ON public.users FOR UPDATE
  USING (auth.uid() = id);

-- Users can insert their own profile (for signup)
CREATE POLICY users_insert_own
  ON public.users FOR INSERT
  WITH CHECK (auth.uid() = id);

-- ============================================================================
-- 11. RLS POLICIES: AGENTS
-- ============================================================================

-- Users can see agents they own or have access to
CREATE POLICY agents_read_accessible
  ON public.agents FOR SELECT
  USING (
    owner_id = auth.uid()
    OR id IN (
      SELECT agent_id FROM public.agent_users WHERE user_id = auth.uid()
    )
  );

-- Only owners can update agents
CREATE POLICY agents_update_own
  ON public.agents FOR UPDATE
  USING (owner_id = auth.uid());

-- Only owners can delete agents
CREATE POLICY agents_delete_own
  ON public.agents FOR DELETE
  USING (owner_id = auth.uid());

-- Only owners can insert agents
CREATE POLICY agents_insert_own
  ON public.agents FOR INSERT
  WITH CHECK (owner_id = auth.uid());

-- ============================================================================
-- 12. RLS POLICIES: AGENT_USERS
-- ============================================================================

-- Users can see their own agent mappings
CREATE POLICY agent_users_read_own
  ON public.agent_users FOR SELECT
  USING (user_id = auth.uid());

-- Agent owners can manage agent_users mappings
CREATE POLICY agent_users_manage_by_owner
  ON public.agent_users FOR ALL
  USING (
    agent_id IN (
      SELECT id FROM public.agents WHERE owner_id = auth.uid()
    )
  );

-- ============================================================================
-- 13. RLS POLICIES: RECORDS
-- ============================================================================

-- Users can read records they created or from accessible agents
CREATE POLICY records_read_own
  ON public.records FOR SELECT
  USING (
    user_id = auth.uid()
    OR agent_id IN (
      SELECT id FROM public.agents WHERE owner_id = auth.uid()
      UNION
      SELECT agent_id FROM public.agent_users WHERE user_id = auth.uid()
    )
  );

-- Users can insert records for themselves
CREATE POLICY records_insert_own
  ON public.records FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Users can pin/unpin only their own records
CREATE POLICY records_update_own_pin
  ON public.records FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Agent owners can insert records for their agents
CREATE POLICY records_insert_agent_owner
  ON public.records FOR INSERT
  WITH CHECK (
    agent_id IN (
      SELECT id FROM public.agents WHERE owner_id = auth.uid()
    )
  );

-- ============================================================================
-- 14. RLS POLICIES: TOKEN_USAGE
-- ============================================================================

-- Users can read token usage for accessible agents
CREATE POLICY token_usage_read_accessible
  ON public.token_usage FOR SELECT
  USING (
    agent_id IN (
      SELECT id FROM public.agents WHERE owner_id = auth.uid()
      UNION
      SELECT agent_id FROM public.agent_users WHERE user_id = auth.uid()
    )
  );

-- Agent owners can insert token usage
CREATE POLICY token_usage_insert_own
  ON public.token_usage FOR INSERT
  WITH CHECK (
    agent_id IN (
      SELECT id FROM public.agents WHERE owner_id = auth.uid()
    )
  );

-- ============================================================================
-- 15. RLS POLICIES: SECTIONS
-- ============================================================================

-- Users have full access to their own sections
CREATE POLICY sections_all_own
  ON public.sections FOR ALL
  USING (user_id = auth.uid());

-- ============================================================================
-- 16. RLS POLICIES: HOME_WIDGETS
-- ============================================================================

-- Users have full access to their own home widgets
CREATE POLICY home_widgets_all_own
  ON public.home_widgets FOR ALL
  USING (user_id = auth.uid());

-- ============================================================================
-- 17. ENABLE REALTIME
-- ============================================================================

-- Enable realtime on records table
ALTER PUBLICATION supabase_realtime ADD TABLE public.records;

-- Enable realtime on agents table
ALTER PUBLICATION supabase_realtime ADD TABLE public.agents;

-- ============================================================================
-- End of 001_initial_schema.sql
-- ============================================================================
