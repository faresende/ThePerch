-- ThePerch Row Level Security Policies
-- Run after 001_initial_schema.sql

-- ──────────────────────────────────────────────────
-- Sections RLS
-- ──────────────────────────────────────────────────
alter table public.sections enable row level security;

create policy "Users can read their own sections"
    on public.sections for select
    using (auth.uid() = user_id);

create policy "Users can insert their own sections"
    on public.sections for insert
    with check (auth.uid() = user_id);

create policy "Users can update their own sections"
    on public.sections for update
    using (auth.uid() = user_id);

create policy "Users can delete their own sections"
    on public.sections for delete
    using (auth.uid() = user_id);

-- ──────────────────────────────────────────────────
-- Dashboard Records RLS
-- ──────────────────────────────────────────────────
alter table public.dashboard_records enable row level security;

create policy "Users can read their own records"
    on public.dashboard_records for select
    using (auth.uid() = user_id);

create policy "Users can insert their own records"
    on public.dashboard_records for insert
    with check (auth.uid() = user_id);

create policy "Users can update their own records"
    on public.dashboard_records for update
    using (auth.uid() = user_id);

create policy "Users can delete their own records"
    on public.dashboard_records for delete
    using (auth.uid() = user_id);

-- ──────────────────────────────────────────────────
-- Service Role Bypass (for agents writing data)
-- Agents use the service_role key, which bypasses RLS.
-- This is intentional — agents write data on behalf of users.
-- ──────────────────────────────────────────────────
-- No additional policies needed. Service role bypasses RLS by default.
