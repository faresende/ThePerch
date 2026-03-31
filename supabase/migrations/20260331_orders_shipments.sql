-- ============================================================================
-- Orders Autopilot v1: orders + shipments tables
-- ============================================================================

create extension if not exists pgcrypto;

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  merchant text not null,
  order_number text not null,
  total numeric(12, 2),
  currency text not null default 'USD',
  status text not null default 'ordered',
  source_email_id text not null,
  confidence numeric(4, 3) not null default 0.5,
  created_at timestamptz not null default now()
);

create table if not exists public.shipments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  tracking_number text not null,
  carrier text not null,
  status text not null default 'label_created',
  created_at timestamptz not null default now()
);

create index if not exists idx_orders_source_email_id
  on public.orders(source_email_id);

create unique index if not exists idx_orders_merchant_order_number_unique
  on public.orders(merchant, order_number);

create index if not exists idx_orders_created_at
  on public.orders(created_at desc);

create index if not exists idx_orders_status
  on public.orders(status);

create index if not exists idx_orders_merchant
  on public.orders(merchant);

create index if not exists idx_shipments_order_id
  on public.shipments(order_id);

create unique index if not exists idx_shipments_order_tracking_unique
  on public.shipments(order_id, tracking_number);

create index if not exists idx_shipments_tracking_number
  on public.shipments(tracking_number);

create index if not exists idx_shipments_carrier_status
  on public.shipments(carrier, status);
