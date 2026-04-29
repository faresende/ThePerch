-- 20260429170724_round8_idle_tx_timeout_at_login_role.sql
--
-- This file matches the migration version that was applied directly to
-- prod (via dashboard) during Round 8. R8 caught the bug in R7 (above)
-- and fixed idle_in_transaction_session_timeout to actually fire by
-- applying it at DATABASE level and on the `authenticator` LOGIN role.
--
-- Round 9 also re-applied this state in
-- `20260429810000_round9_repo_state_sync.sql`. This stub is here so
-- `supabase db push` against prod doesn't refuse for "missing
-- migration files." All statements are idempotent.

ALTER DATABASE postgres   SET idle_in_transaction_session_timeout = '60s';
ALTER ROLE     authenticator SET idle_in_transaction_session_timeout = '60s';
