-- 20260423180946_prune_agent_runs_and_drop_legacy_orders_cols.sql
--
-- Stub committed in Round 11 to match the prod migration ledger version
-- of the same name. The original was applied directly via the dashboard.
-- All statements below are idempotent (CREATE OR REPLACE / DROP IF EXISTS),
-- so re-running on a fresh install converges on the same end state.

BEGIN;

-- ─── 1. Pruning RPC ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.prune_agent_runs_older_than(days integer DEFAULT 90)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  n integer;
BEGIN
  DELETE FROM public.agent_runs
  WHERE status = 'ok'
    AND started_at < now() - (days::text || ' days')::interval
  RETURNING 1 INTO n;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

COMMENT ON FUNCTION public.prune_agent_runs_older_than(integer) IS
  'Delete agent_runs rows where status=ok AND older than N days. Never deletes error/partial/timeout rows.';

GRANT EXECUTE ON FUNCTION public.prune_agent_runs_older_than(integer) TO service_role;

-- ─── 2. Drop legacy orders/shipments columns ─────────────────────────────

ALTER TABLE public.orders DROP COLUMN IF EXISTS merchant;
ALTER TABLE public.orders DROP COLUMN IF EXISTS order_number;
ALTER TABLE public.orders DROP COLUMN IF EXISTS total;
ALTER TABLE public.orders DROP COLUMN IF EXISTS source_email_id;
ALTER TABLE public.orders DROP COLUMN IF EXISTS confidence;

COMMIT;
