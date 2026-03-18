-- ThePerch Initial Schema
-- Run this in your Supabase SQL Editor to set up the database.

-- ──────────────────────────────────────────────────
-- Extensions
-- ──────────────────────────────────────────────────
create extension if not exists "uuid-ossp";

-- ──────────────────────────────────────────────────
-- Sections
-- Controls which tabs appear in the app and their order.
-- ──────────────────────────────────────────────────
create table if not exists public.sections (
    id          uuid primary key default uuid_generate_v4(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    slug        text not null,
    display_name text not null,
    sort_order  integer not null default 0,
    is_visible  boolean not null default true,
    config      jsonb,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

create index if not exists sections_user_id_idx on public.sections(user_id);
create unique index if not exists sections_user_slug_idx on public.sections(user_id, slug);

-- ──────────────────────────────────────────────────
-- Dashboard Records
-- Core data table. All agent-written data lives here.
-- ──────────────────────────────────────────────────
create table if not exists public.dashboard_records (
    id          uuid primary key default uuid_generate_v4(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    agent_id    text not null,
    type        text not null,
    category    text not null,
    title       text not null default '',
    data        jsonb not null default '{}',
    display_hint text not null default 'single_value',
    annotations jsonb,
    pinned      boolean not null default false,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now(),
    expires_at  timestamptz
);

create index if not exists dashboard_records_user_id_idx on public.dashboard_records(user_id);
create index if not exists dashboard_records_type_idx on public.dashboard_records(type);
create index if not exists dashboard_records_category_idx on public.dashboard_records(category);
create index if not exists dashboard_records_created_at_idx on public.dashboard_records(created_at desc);

-- Auto-update updated_at on row change
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger sections_updated_at
    before update on public.sections
    for each row execute function public.set_updated_at();

create trigger dashboard_records_updated_at
    before update on public.dashboard_records
    for each row execute function public.set_updated_at();
