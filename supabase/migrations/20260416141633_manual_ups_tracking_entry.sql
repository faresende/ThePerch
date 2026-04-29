-- Historical: manual UPS tracking entry from before the orders-autopilot
-- pipeline existed. Original purpose was to seed a single in-transit
-- order so the maintainer's Hub > Orders UI had something to render
-- pre-pipeline.
--
-- For fresh installs this would create a synthetic UPS order under a
-- placeholder zero-UUID user that doesn't exist in `auth.users`. The
-- guard below skips the insert unless that placeholder user actually
-- exists — keeping the migration idempotent for the maintainer's
-- existing database while turning it into a no-op everywhere else.

BEGIN;

DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = '00000000-0000-0000-0000-000000000000'::uuid
  ) THEN
    RAISE NOTICE 'manual_ups_tracking_entry: placeholder user not present, skipping';
    RETURN;
  END IF;

WITH upserted_order AS (
  INSERT INTO public.orders (
    user_id,
    merchant_name,
    normalized_merchant,
    order_number,
    order_date,
    total_amount,
    currency,
    source_email_ids,
    confidence_score,
    status,
    merchant,
    total,
    source_email_id,
    confidence,
    created_at,
    updated_at
  )
  VALUES (
    '00000000-0000-0000-0000-000000000000'::uuid,
    'UPS',
    'ups',
    '1Z3F1A720400081100',
    NOW(),
    NULL,
    'USD',
    ARRAY['hermes_manual_tracking_add'],
    1.0,
    'shipped',
    'UPS',
    NULL,
    'hermes_manual_tracking_add',
    1.0,
    NOW(),
    NOW()
  )
  ON CONFLICT (merchant, order_number)
  DO UPDATE SET
    user_id = EXCLUDED.user_id,
    merchant_name = EXCLUDED.merchant_name,
    normalized_merchant = EXCLUDED.normalized_merchant,
    order_date = COALESCE(public.orders.order_date, EXCLUDED.order_date),
    total_amount = EXCLUDED.total_amount,
    currency = EXCLUDED.currency,
    source_email_ids = EXCLUDED.source_email_ids,
    confidence_score = GREATEST(COALESCE(public.orders.confidence_score, 0), EXCLUDED.confidence_score),
    status = EXCLUDED.status,
    merchant = EXCLUDED.merchant,
    total = EXCLUDED.total,
    source_email_id = EXCLUDED.source_email_id,
    confidence = GREATEST(COALESCE(public.orders.confidence, 0), EXCLUDED.confidence),
    updated_at = NOW()
  RETURNING id
)
INSERT INTO public.shipments (
  order_id,
  tracking_number,
  carrier,
  seventeen_track_id,
  status,
  latest_checkpoint,
  shipped_at,
  delivered_at,
  source_email_ids,
  confidence_score,
  created_at,
  updated_at
)
SELECT
  id,
  '1Z3F1A720400081100',
  'UPS',
  NULL,
  'in_transit',
  'Added manually from a UPS tracking URL (pre-autopilot seed).',
  NOW(),
  NULL,
  ARRAY['hermes_manual_tracking_add'],
  1.0,
  NOW(),
  NOW()
FROM upserted_order
ON CONFLICT (order_id, tracking_number)
DO UPDATE SET
  carrier = EXCLUDED.carrier,
  status = EXCLUDED.status,
  latest_checkpoint = EXCLUDED.latest_checkpoint,
  shipped_at = COALESCE(public.shipments.shipped_at, EXCLUDED.shipped_at),
  delivered_at = EXCLUDED.delivered_at,
  source_email_ids = EXCLUDED.source_email_ids,
  confidence_score = GREATEST(COALESCE(public.shipments.confidence_score, 0), EXCLUDED.confidence_score),
  updated_at = NOW();
END;
$do$;

COMMIT;
