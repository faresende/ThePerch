-- 20260423181015_restore_order_number_column.sql
--
-- Stub committed in Round 11 to match the prod migration ledger.
-- Restores `orders.order_number` that the previous migration dropped
-- by accident. Idempotent.

BEGIN;

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS order_number TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_user_merchant_number_unique
  ON public.orders (user_id, normalized_merchant, order_number)
  WHERE order_number IS NOT NULL AND user_id IS NOT NULL;

COMMIT;
