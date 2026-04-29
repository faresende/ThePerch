# Managed Tier Setup Guide

The managed tier is a shared Supabase instance that ThePerch Cloud users connect to.
Users don't need to create their own Supabase project — they just sign up and get an account.

## Architecture

```
User signs up in app
       ↓
Supabase Auth creates auth.users entry
       ↓
on_auth_user_created trigger fires
       ↓
profiles row created
provision_new_user() seeds default sections
       ↓
User can start logging data immediately
```

Row Level Security ensures each user can only read/write their own data.

## Setup Steps

### 1. Create a new Supabase project for the managed tier

- Go to supabase.com → New Project
- Name: "ThePerch Cloud" (or similar)
- Note the project URL and both keys (anon + service_role)

### 2. Run migrations in order

In Supabase SQL Editor:
1. `001_initial_schema.sql`
2. `002_rls_policies.sql`
3. `003_managed_tier.sql`

### 3. Enable Auth providers

In Supabase Dashboard → Authentication → Providers:
- Email (enable)
- Apple (configure with your Apple Developer credentials)
- Google (optional)

### 4. Update app configuration

Add the managed tier Supabase URL and anon key to the app's OnboardingView as the "ThePerch Cloud" option. When a user selects "ThePerch Cloud", these credentials are used instead of requiring them to enter their own.

The anon key for the managed tier can be embedded in the app binary (it's safe — RLS protects the data). The service_role key must never be in the app.

### 5. Environment variables for server-side provisioning

If you build a server-side Edge Function for advanced provisioning:
```
MANAGED_SUPABASE_URL=https://yourproject.supabase.co
MANAGED_SUPABASE_SERVICE_ROLE_KEY=...  # Never in the app
```

## Tier Limits (suggested)

| Tier | Records/day | Storage | Price |
|------|------------|---------|-------|
| Free | 50 | 100MB | Free |
| Pro  | Unlimited | 1GB | $5/mo |
| Team | Unlimited | 10GB | $20/mo |

These are suggestions. Implement via the `profiles.tier` column + server-side checks.

## Security Notes

- The service_role key bypasses RLS. Never put it in the iOS app.
- The anon key respects RLS. Safe to embed in app.
- All agent writes should use the service_role key (server-side only).
- Users can only read/write their own data even if they know the anon key.
