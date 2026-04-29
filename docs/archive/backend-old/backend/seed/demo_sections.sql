-- ThePerch Demo Sections Seed
-- Replace <YOUR_USER_UUID> with your Supabase auth.users UUID before running.
-- Find it in the Supabase dashboard: Authentication > Users.

do $$
declare
    uid uuid := '<YOUR_USER_UUID>'; -- Replace this
begin
    insert into public.sections (user_id, slug, display_name, sort_order, is_visible)
    values
        (uid, 'home',        'The Perch',  0, true),
        (uid, 'health',      'Health',     1, true),
        (uid, 'workouts',    'Workouts',   2, true),
        (uid, 'deliveries',  'Deliveries', 3, true),
        (uid, 'calendar',    'Calendar',   4, true),
        (uid, 'travel',      'Travel',     5, true),
        (uid, 'bookmarks',   'Bookmarks',  6, true),
        (uid, 'admin',       'Admin',      7, false),
        (uid, 'legal',       'Legal',      8, false)
    on conflict (user_id, slug) do nothing;
end $$;
