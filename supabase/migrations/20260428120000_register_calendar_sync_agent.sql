-- 20260428120000_register_calendar_sync_agent.sql
--
-- (Historical) The calendar-sync agent used to be inserted here with a
-- hardcoded owner_id, which (a) leaked the maintainer's user UUID into
-- the public repo and (b) failed on replay against any other Supabase
-- project where that UUID doesn't exist.
--
-- The runtime now auto-registers any agent on first `insert_agent_run`
-- (see agents/health-integrations/_supabase_client.py:_ensure_agent_registered),
-- so this migration is a no-op left in place purely for sequence
-- continuity.

-- intentionally empty
SELECT 1;
