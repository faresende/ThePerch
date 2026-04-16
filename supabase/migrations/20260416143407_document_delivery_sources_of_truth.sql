-- Document canonical vs legacy storage surfaces for ThePerch.
-- Safe metadata-only migration: adds comments, does not rewrite data.

BEGIN;

COMMENT ON TABLE public.dashboard_records IS
  'Generic dashboard/app card feed. Use for measurements, meals, events, bookmarks, status, notes, and similar cards. Do not use as the default source of truth for new tracked packages; tracked deliveries should use public.orders + public.shipments. Delivery rows here are legacy compatibility only.';

COMMENT ON TABLE public.orders IS
  'Canonical order-level model for tracked deliveries shown in the app Orders surface.';

COMMENT ON TABLE public.shipments IS
  'Canonical shipment/tracking model for tracked deliveries shown in the app Orders surface.';

COMMENT ON TABLE public.records IS
  'Legacy pre-dashboard_records table. Retained for historical migrations and existing foreign-key references. Do not use for new product features.';

COMMIT;
