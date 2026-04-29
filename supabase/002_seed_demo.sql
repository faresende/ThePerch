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

-- Fresh-install guard: the rest of this seed inserts rows whose FKs
-- reference auth.users(id) (via public.users.id and public.agents.owner_id).
-- If the placeholder UUID hasn't been replaced with a real auth user
-- yet, every INSERT below will fail with a 23503 FK violation. Skip
-- with a NOTICE so SETUP-FOR-AGENTS Step 3 is the natural next step
-- rather than a stack trace.
IF NOT EXISTS (
  SELECT 1 FROM auth.users WHERE id = demo_user_id
) THEN
  RAISE NOTICE
    '002_seed_demo: demo_user_id (%) not present in auth.users yet — skipping seed. Create the auth user first (SETUP-FOR-AGENTS.md Step 3), edit this file with the real UUID, and re-run.',
    demo_user_id;
  RETURN;
END IF;

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

-- Note: agent IDs `main`, `biochecha`, `calendario`, `entregas`, `legal`
-- are canonical internal identifiers referenced throughout the iOS app
-- and Python agent scripts. Don't rename — they're project-internal
-- string IDs, not user-visible labels. The display_name fields below
-- are the user-visible labels and are kept generic.
INSERT INTO public.agents (id, display_name, emoji, model, owner_id, is_active)
VALUES
  ('main',       'Main',     '🦞', 'claude-opus-4-7',   demo_user_id, true),
  ('biochecha',  'Health',   '💪', 'claude-opus-4-7',   demo_user_id, true),
  ('calendario', 'Calendar', '📅', 'claude-sonnet-4-7', demo_user_id, true),
  ('entregas',   'Orders',   '📦', 'claude-sonnet-4-7', demo_user_id, true),
  ('legal',      'Legal',    '⚖️', 'claude-sonnet-4-7', demo_user_id, true)
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  emoji = EXCLUDED.emoji,
  model = EXCLUDED.model;

-- ============================================================================
-- 3. INSERT AGENT_USERS MAPPINGS (Demo User as admin of all agents)
-- ============================================================================

INSERT INTO public.agent_users (agent_id, user_id, role)
VALUES
  ('main',       demo_user_id, 'admin'),
  ('biochecha',  demo_user_id, 'admin'),
  ('calendario', demo_user_id, 'admin'),
  ('entregas',   demo_user_id, 'admin'),
  ('legal',      demo_user_id, 'admin')
ON CONFLICT (agent_id, user_id) DO UPDATE SET
  role = EXCLUDED.role;

-- ============================================================================
-- 4. INSERT DEFAULT SECTIONS
-- ============================================================================

INSERT INTO public.sections (user_id, slug, display_name, sort_order, is_visible, config)
VALUES
  (demo_user_id, 'home',       'Home',       0, true, '{"description": "Dashboard of dashboards"}'::jsonb),
  (demo_user_id, 'health',     'Health',     1, true, '{"agent": "biochecha"}'::jsonb),
  (demo_user_id, 'deliveries', 'Deliveries', 2, true, '{"agent": "entregas"}'::jsonb),
  (demo_user_id, 'calendar',   'Calendar',   3, true, '{"agent": "calendario"}'::jsonb),
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
