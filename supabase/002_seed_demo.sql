-- ============================================================================
-- The Perch — Demo Seed Data
-- ============================================================================
-- This seed sets up a minimal, working configuration for a brand-new user.
-- It assumes:
--   1) You have already run 001_initial_schema.sql.
--   2) You have signed up through the app (or via Supabase Auth) so that an
--      auth.users row exists for you.
--
-- HOW TO RUN:
--   1) Find your Supabase Auth user UUID:
--        SELECT id FROM auth.users ORDER BY created_at DESC LIMIT 1;
--      Or in the Supabase dashboard: Authentication → Users → copy the ID.
--   2) Replace <YOUR_USER_UUID> below with that UUID.
--   3) Paste the whole file into the Supabase SQL Editor and run it.
--
-- The seed is idempotent — rerunning it is safe.
-- ============================================================================

DO $$
DECLARE
  owner_id uuid := '<YOUR_USER_UUID>'::uuid;  -- <-- replace before running
BEGIN

-- ----------------------------------------------------------------------------
-- 1. User profile
-- ----------------------------------------------------------------------------

INSERT INTO public.users (id, display_name, preferences)
VALUES (
  owner_id,
  'Me',
  '{
    "theme": "light",
    "language": "en",
    "notifications": true,
    "timezone": "UTC"
  }'::jsonb
)
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  preferences = EXCLUDED.preferences;

-- ----------------------------------------------------------------------------
-- 2. Agents — a minimal set you can extend
-- ----------------------------------------------------------------------------

INSERT INTO public.agents (id, display_name, emoji, model, owner_id, is_active)
VALUES
  ('assistant',  'Assistant',  '🤖', 'claude-opus-4.7',   owner_id, true),
  ('health',     'Health',     '❤️', 'claude-sonnet-4.6', owner_id, true),
  ('calendar',   'Calendar',   '📅', 'claude-sonnet-4.6', owner_id, true),
  ('deliveries', 'Deliveries', '📦', 'claude-sonnet-4.6', owner_id, true)
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  emoji = EXCLUDED.emoji,
  model = EXCLUDED.model;

-- ----------------------------------------------------------------------------
-- 3. Agent-user mappings (you as admin of all demo agents)
-- ----------------------------------------------------------------------------

INSERT INTO public.agent_users (agent_id, user_id, role)
VALUES
  ('assistant',  owner_id, 'admin'),
  ('health',     owner_id, 'admin'),
  ('calendar',   owner_id, 'admin'),
  ('deliveries', owner_id, 'admin')
ON CONFLICT (agent_id, user_id) DO UPDATE SET
  role = EXCLUDED.role;

-- ----------------------------------------------------------------------------
-- 4. Default sections / tabs
-- ----------------------------------------------------------------------------
-- Hide the sections you don't use. `is_visible = false` keeps the row so you
-- can toggle them back on later without re-seeding.

INSERT INTO public.sections (user_id, slug, display_name, sort_order, is_visible, config)
VALUES
  (owner_id, 'home',       'Home',       0, true,  '{"description": "Dashboard of dashboards"}'::jsonb),
  (owner_id, 'health',     'Health',     1, true,  '{"agent": "health"}'::jsonb),
  (owner_id, 'deliveries', 'Deliveries', 2, true,  '{"agent": "deliveries"}'::jsonb),
  (owner_id, 'calendar',   'Calendar',   3, true,  '{"agent": "calendar"}'::jsonb),
  (owner_id, 'bookmarks',  'Bookmarks',  4, false, '{"agent": "assistant"}'::jsonb)
  -- NOTE: `admin` and `legal` sections were dropped on 2026-04-23. Admin
  -- functionality now lives inline under DebugAdminView in SettingsTab;
  -- legal was never surfaced as a section in the current iOS layout.
ON CONFLICT (user_id, slug) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  sort_order   = EXCLUDED.sort_order,
  is_visible   = EXCLUDED.is_visible,
  config       = EXCLUDED.config;

END $$;

-- ============================================================================
-- End of 002_seed_demo.sql
-- ============================================================================
