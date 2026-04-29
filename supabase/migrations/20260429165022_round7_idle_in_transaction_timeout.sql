-- 20260429165022_round7_idle_in_transaction_timeout.sql
--
-- This file exists to match the migration version that was applied
-- directly to prod (via dashboard) during Round 7. The original R7 fix
-- was buggy — it set idle_in_transaction_session_timeout on the
-- `authenticated` and `anon` roles, both of which are NOLOGIN, so the
-- GUC never fired. R8 fixed the bug by applying the setting at
-- DATABASE level + on the `authenticator` LOGIN role
-- (`20260429810000_round9_repo_state_sync.sql`).
--
-- The R7 migration ledger row in prod still references this version
-- though, so we keep this file as a no-op stub so `supabase db push`
-- against prod doesn't refuse to push for "missing migration files."
-- Re-running the stale ALTER ROLE statements is harmless: it sets a
-- GUC on a NOLOGIN role that never fires.

ALTER ROLE authenticated SET idle_in_transaction_session_timeout = '60s';
ALTER ROLE anon          SET idle_in_transaction_session_timeout = '60s';
