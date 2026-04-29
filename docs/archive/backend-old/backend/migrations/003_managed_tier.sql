-- ThePerch Managed Tier Schema
-- Run this on the SHARED multi-tenant Supabase project (not self-hosted)
-- This extends 001_initial_schema.sql with managed-tier-specific additions

-- ──────────────────────────────────────────────────
-- User profiles (extends Supabase auth.users)
-- ──────────────────────────────────────────────────
create table if not exists public.profiles (
    id          uuid primary key references auth.users(id) on delete cascade,
    display_name text,
    tier        text not null default 'free' check (tier in ('free', 'pro', 'team')),
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

create trigger profiles_updated_at
    before update on public.profiles
    for each row execute function public.set_updated_at();

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
    insert into public.profiles (id, display_name)
    values (new.id, new.raw_user_meta_data->>'display_name');
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- RLS for profiles
alter table public.profiles enable row level security;

create policy "Users can read own profile"
    on public.profiles for select
    using (auth.uid() = id);

create policy "Users can update own profile"
    on public.profiles for update
    using (auth.uid() = id);

-- ──────────────────────────────────────────────────
-- Provisioning function
-- Seeds default sections for a new user.
-- Call this after sign-up (from server-side only).
-- ──────────────────────────────────────────────────
create or replace function public.provision_new_user(p_user_id uuid)
returns void language plpgsql security definer as $$
begin
    insert into public.sections (user_id, slug, display_name, sort_order, is_visible)
    values
        (p_user_id, 'home',        'The Perch',  0, true),
        (p_user_id, 'health',      'Health',     1, true),
        (p_user_id, 'workouts',    'Workouts',   2, true),
        (p_user_id, 'deliveries',  'Deliveries', 3, true),
        (p_user_id, 'calendar',    'Calendar',   4, true),
        (p_user_id, 'travel',      'Travel',     5, false),
        (p_user_id, 'bookmarks',   'Bookmarks',  6, false),
        (p_user_id, 'admin',       'Admin',      7, false),
        (p_user_id, 'legal',       'Legal',      8, false)
    on conflict (user_id, slug) do nothing;
end;
$$;

-- ──────────────────────────────────────────────────
-- Usage limits view (for rate limiting)
-- ──────────────────────────────────────────────────
create or replace view public.user_usage as
select
    user_id,
    count(*) as total_records,
    count(*) filter (where created_at >= now() - interval '24 hours') as records_today,
    count(*) filter (where created_at >= now() - interval '30 days') as records_this_month,
    max(created_at) as last_record_at
from public.dashboard_records
group by user_id;
