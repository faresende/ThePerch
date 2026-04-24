-- Relax legacy NOT NULL constraints on orders and shipments so the
-- TypeScript orders-autopilot classifier — which writes only the new-schema
-- columns (merchant_name, normalized_merchant, source_email_ids[],
-- confidence_score) — can insert without tripping over the legacy
-- single-valued columns (merchant, order_number, source_email_id, confidence).
--
-- The legacy global unique index on (merchant, order_number) is dropped and
-- replaced with a per-user partial unique on (user_id, normalized_merchant,
-- order_number) — only enforced when order_number is present. Application-
-- layer dedupe (orders-store.upsertOrder) handles the order_number-missing
-- case via a pre-query.

BEGIN;

ALTER TABLE public.orders    ALTER COLUMN merchant        DROP NOT NULL;
ALTER TABLE public.orders    ALTER COLUMN order_number    DROP NOT NULL;
ALTER TABLE public.orders    ALTER COLUMN source_email_id DROP NOT NULL;
ALTER TABLE public.orders    ALTER COLUMN confidence      DROP NOT NULL;
ALTER TABLE public.shipments ALTER COLUMN carrier         DROP NOT NULL;

DROP INDEX IF EXISTS idx_orders_merchant_order_number_unique;

CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_user_merchant_number_unique
  ON public.orders (user_id, normalized_merchant, order_number)
  WHERE order_number IS NOT NULL AND user_id IS NOT NULL;

COMMIT;
