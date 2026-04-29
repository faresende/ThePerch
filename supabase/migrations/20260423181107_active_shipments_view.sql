-- 20260423181107_active_shipments_view.sql
--
-- Stub committed in Round 11 to match the prod migration ledger.
-- Server-side projection of "active shipments per order" for the iOS
-- DeliveryHomeCard. Idempotent (CREATE OR REPLACE VIEW).

CREATE OR REPLACE VIEW public.active_shipments_summary AS
SELECT
  o.id                          AS order_id,
  o.user_id,
  o.merchant_name,
  o.normalized_merchant,
  o.order_number,
  o.order_date,
  o.total_amount,
  o.currency,
  o.status                      AS order_status,
  o.manual_delivered_at,
  o.created_at                  AS order_created_at,
  o.updated_at                  AS order_updated_at,
  -- Primary shipment = most-recently-updated shipment for this order
  s.id                          AS shipment_id,
  s.tracking_number,
  s.carrier,
  s.status                      AS shipment_status,
  s.latest_checkpoint,
  s.tracking_url,
  s.shipped_at,
  s.delivered_at,
  s.updated_at                  AS shipment_updated_at
FROM public.orders o
LEFT JOIN LATERAL (
  SELECT *
  FROM public.shipments
  WHERE order_id = o.id
  ORDER BY updated_at DESC
  LIMIT 1
) s ON TRUE
WHERE
  o.manual_delivered_at IS NULL
  AND o.status NOT IN ('delivered', 'cancelled')
  AND (
    s.id IS NOT NULL
    OR o.created_at > now() - interval '30 days'
  )
ORDER BY
  COALESCE(s.updated_at, o.updated_at) DESC;

COMMENT ON VIEW public.active_shipments_summary IS
  'Pre-joined active orders + their latest shipment for the iOS DeliveryHomeCard. RLS passes through from underlying tables.';
