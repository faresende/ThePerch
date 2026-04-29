-- 20260429153949_replica_identity_default.sql
--
-- Stub committed in Round 11 to match the prod migration ledger.
-- iOS subscribers only read insertion.record / update.record (NEW row,
-- full payload — unaffected by REPLICA IDENTITY) and deletion.oldRecord["id"]
-- (just the PK, which DEFAULT publishes too). FULL was overkill — every
-- UPDATE was writing the whole pre-image to WAL for no benefit.

ALTER TABLE public.dashboard_records REPLICA IDENTITY DEFAULT;
ALTER TABLE public.agents             REPLICA IDENTITY DEFAULT;
