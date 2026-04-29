-- ============================================================================
-- The Perch - the demo user's Initial Setup Seed Data
-- ============================================================================
-- IMPORTANT: Before running, replace the placeholder ID below with your
-- actual Supabase Auth user ID. You can find it in the Supabase dashboard:
--   Authentication > Users > click your user > copy the UUID
-- Or run: SELECT id FROM auth.users LIMIT 1;
-- ============================================================================

-- ============================================================================
-- 0. SET YOUR USER ID HERE (one place to change)
-- ============================================================================

DO $$
DECLARE
  demo_user_id uuid := '00000000-0000-0000-0000-000000000000';  -- the demo user's auth.users UUID
BEGIN

-- ============================================================================
-- 1. INSERT THE DEMO USER'S USER PROFILE
-- ============================================================================

INSERT INTO public.users (id, display_name, preferences)
VALUES (
  demo_user_id,
  'Demo User',
  '{
    "theme": "light",
    "language": "pt-BR",
    "notifications": true,
    "timezone": "Europe/Lisbon"
  }'::jsonb
)
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  preferences = EXCLUDED.preferences;

-- ============================================================================
-- 2. INSERT AGENTS
-- ============================================================================

INSERT INTO public.agents (id, display_name, emoji, model, owner_id, is_active)
VALUES
  ('main',       'Main',       '🦞', 'claude-opus-4-7',   demo_user_id, true),
  ('health',     'Health',     '💪', 'claude-opus-4-7',   demo_user_id, true),
  ('calendar',   'Calendar',   '📅', 'claude-sonnet-4-7', demo_user_id, true),
  ('orders',     'Orders',     '📦', 'claude-sonnet-4-7', demo_user_id, true),
  ('legal',      'Legal',      '⚖️', 'claude-sonnet-4-7', demo_user_id, true)
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  emoji = EXCLUDED.emoji,
  model = EXCLUDED.model;

-- ============================================================================
-- 3. INSERT AGENT_USERS MAPPINGS (Demo User as admin of all agents)
-- ============================================================================

INSERT INTO public.agent_users (agent_id, user_id, role)
VALUES
  ('main',     demo_user_id, 'admin'),
  ('health',   demo_user_id, 'admin'),
  ('calendar', demo_user_id, 'admin'),
  ('orders',   demo_user_id, 'admin'),
  ('legal',    demo_user_id, 'admin')
ON CONFLICT (agent_id, user_id) DO UPDATE SET
  role = EXCLUDED.role;

-- ============================================================================
-- 4. INSERT DEFAULT SECTIONS
-- ============================================================================

INSERT INTO public.sections (user_id, slug, display_name, sort_order, is_visible, config)
VALUES
  (demo_user_id, 'home',       'Home',       0, true, '{"description": "Dashboard of dashboards"}'::jsonb),
  (demo_user_id, 'health',     'Health',     1, true, '{"agent": "health"}'::jsonb),
  (demo_user_id, 'deliveries', 'Deliveries', 2, true, '{"agent": "orders"}'::jsonb),
  (demo_user_id, 'calendar',   'Calendar',   3, true, '{"agent": "calendar"}'::jsonb),
  (demo_user_id, 'bookmarks',  'Bookmarks',  4, true, '{"agent": "main"}'::jsonb),
  (demo_user_id, 'admin',      'Admin',      5, true, '{"tabs": ["agents", "token_usage"]}'::jsonb),
  (demo_user_id, 'legal',      'Legal',      6, true, '{"agent": "legal"}'::jsonb)
ON CONFLICT (user_id, slug) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  sort_order = EXCLUDED.sort_order,
  config = EXCLUDED.config;

END $$;

-- ============================================================================
-- End of 002_seed_demo.sql
-- ============================================================================
