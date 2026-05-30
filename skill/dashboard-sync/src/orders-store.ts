/**
 * orders-store.ts
 * Typed UPSERT helpers for orders, shipments, and review_items tables.
 */

import { supabase } from './supabase';
import type { ParseTrace } from './parse-trace';

// ─── Types ──────────────────────────────────────────────────────────────────

export type OrderStatus =
  | 'ordered'
  | 'processing'
  | 'shipped_partial'
  | 'shipped'
  | 'delivered'
  | 'cancelled'
  | 'issue'
  // Phase-1 corrections-and-rules additions (2026-04-27):
  | 'digital'              // Apple-bug fix: digital purchase, no shipment expected
  | 'dismissed_by_user';   // soft-delete via "Not an order" swipe correction

export type ShipmentStatus =
  | 'unknown'
  | 'label_created'
  | 'in_transit'
  | 'out_for_delivery'
  | 'delivered'
  | 'exception';

export type ReviewItemType =
  | 'duplicate_order'
  | 'orphan_shipment'
  | 'order_no_shipment'
  | 'shipment_no_order'
  | 'low_confidence_match'
  | 'other';

export interface OrderRecord {
  id?: string;
  user_id: string;
  merchant_name: string;
  normalized_merchant: string;
  order_number: string | null;
  order_date: string | null;
  total_amount: number | null;
  currency: string;
  source_email_ids: string[];
  confidence_score: number;
  status: OrderStatus;
  // Classification-rework fields (order-tracker rework). The cascade
  // decides physical/digital/unsure; the disposition mapper stamps
  // these so iOS surfaces ONLY physical packages. All optional —
  // legacy/manual call-sites may omit them and the columns carry DB
  // defaults (hidden defaults false). upsertOrder writes them through
  // only when present (the null-strip update path preserves prior
  // values on re-classification).
  classification?: string;       // 'physical' | 'digital' | 'unsure'
  hidden?: boolean;              // true → kept out of the surfaced tracker
  hidden_reason?: string | null; // cascade reason for a hidden row, e.g. 'hard-category:airline'
  // Per-row audit trail of every parser decision. Schema in
  // src/parse-trace.ts (`ParseTrace`). Optional because legacy
  // call-sites (e.g. review-queue manual confirmations) may not
  // populate one; column allows NULL for compatibility.
  parse_trace?: ParseTrace | null;
  created_at?: string;
  updated_at?: string;
}

export interface ShipmentRecord {
  id?: string;
  order_id: string;
  tracking_number: string;
  carrier: string | null;
  tracking_url: string | null;
  seventeen_track_id: string | null;
  status: ShipmentStatus;
  latest_checkpoint: string | null;
  shipped_at: string | null;
  delivered_at: string | null;
  source_email_ids: string[];
  confidence_score: number;
  // Phase 1 ETA (2026-04-27): expected delivery date sourced from
  // either carrier-email regex extraction or 17track polling.
  // Resolved via scanner-side resolveETAUpdate (priority + recency).
  eta_at?: string | null;            // ISO 8601
  eta_source?: '17track' | 'email' | 'heuristic' | null;
  eta_recorded_at?: string | null;   // ISO 8601
  created_at?: string;
  updated_at?: string;
}

/**
 * Generate a carrier-specific tracking URL for known carriers.
 * Returns null for unknown/unsupported carriers (client falls back to 17track).
 */
export function carrierTrackingURL(carrier: string | null, trackingNumber: string): string | null {
  if (!carrier || !trackingNumber) return null;
  const c = carrier.toUpperCase();

  if (c.includes('FEDEX') || c.includes('FEDERAL EXPRESS'))
    return `https://www.fedex.com/fedextrack/?trknbr=${trackingNumber}`;
  if (c.includes('DHL'))
    return `https://www.dhl.com/pt-en/home/tracking.html?tracking-id=${trackingNumber}&submit=1`;
  if (c.includes('UPS'))
    return `https://www.ups.com/track?trackNums=${trackingNumber}`;
  if (c.includes('CTT') || c.includes('CORREIOS'))
    return `https://www.ctt.pt/track-and-trace?trackingId=${trackingNumber}`;
  if (c.includes('USPS'))
    return `https://www.usps.com/tracking/${trackingNumber}`;
  if (c.includes('DPD'))
    return `https://tracking.dpd.de/status/en_US/parcel/${trackingNumber}`;
  if (c.includes('GLS'))
    return `https://gls-group.eu/EN/track-and-trace?match=${trackingNumber}`;
  if (c.includes('POST.NL') || c.includes('POSTNL'))
    return `https://postnl.nl/tracktrace/${trackingNumber}/NL`;
  if (c.includes('SENDCLOUD'))
    return `https://tracking.sendcloud.sc/forward/${trackingNumber}`;

  return null;
}

export interface ReviewItemRecord {
  id?: string;
  user_id: string;
  type: ReviewItemType;
  related_order_id: string | null;
  related_shipment_id: string | null;
  reason: string;
  suggested_action: string | null;
  confidence_score: number;
  resolved_at?: string | null;
  created_at?: string;
  updated_at?: string;

  // Source-of-truth columns added 2026-04-26 so the iOS review queue
  // can render rows and take action without parsing `reason` text.
  // All optional — existing rows pre-migration have these as null.
  source_email_id?: string | null;
  source_subject?: string | null;
  source_sender_email?: string | null;
  source_sender_name?: string | null;
  suggested_merchant?: string | null;
  suggested_order_number?: string | null;
  suggested_total_amount?: number | null;
  suggested_currency?: string | null;
}

// ─── Order Items (Tier 4) ───────────────────────────────────────────────

/** Per-line item on an order — what the user actually purchased. */
export interface OrderItemRecord {
  id?: string;
  order_id: string;
  name: string;
  quantity: number;
  unit_price: number | null;
  currency: string | null;
  position: number;
  raw_line?: string | null;
  created_at?: string;
  updated_at?: string;
}

/**
 * Replace all items on an order with the new list. Used when re-running
 * the LLM extractor against a re-classified email — we delete-then-insert
 * rather than upsert because items don't have a stable identity (the
 * LLM might rename "Tasche Camera Bag" to "Demo Merchant Tasche" between
 * runs and we'd rather have one canonical list than two near-duplicates).
 *
 * No-op when `items` is empty (some emails are real orders with no
 * extractable line items — e.g. a subscription renewal — and we don't
 * want to wipe a previously-extracted list in that case).
 */
export async function replaceOrderItems(
  orderId: string,
  items: Array<Omit<OrderItemRecord, 'id' | 'order_id' | 'created_at' | 'updated_at' | 'position'>>,
): Promise<void> {
  if (items.length === 0) return;

  // Wipe previous items for this order; the LLM's latest run is the
  // source of truth.
  const { error: delError } = await supabase
    .from('order_items')
    .delete()
    .eq('order_id', orderId);
  if (delError) throw new Error(`Failed to clear order_items: ${delError.message}`);

  const now = new Date().toISOString();
  const rows: OrderItemRecord[] = items.map((it, idx) => ({
    order_id: orderId,
    name: it.name,
    quantity: it.quantity,
    unit_price: it.unit_price,
    currency: it.currency,
    position: idx,
    raw_line: it.raw_line ?? null,
    created_at: now,
    updated_at: now,
  }));

  const { error: insError } = await supabase.from('order_items').insert(rows);
  if (insError) throw new Error(`Failed to insert order_items: ${insError.message}`);
}

/** Fetch all items for an order, in display order. */
export async function getOrderItems(orderId: string): Promise<OrderItemRecord[]> {
  const { data, error } = await supabase
    .from('order_items')
    .select('*')
    .eq('order_id', orderId)
    .order('position', { ascending: true });
  if (error) throw new Error(`Failed to get order_items: ${error.message}`);
  return (data ?? []) as OrderItemRecord[];
}

// ─── Order helpers ─────────────────────────────────────────────────────────

/**
 * Upsert an order. Returns the order ID.
 */
export async function upsertOrder(order: OrderRecord): Promise<{ id: string; isNew: boolean }> {
  const now = new Date().toISOString();

  // Fast path: order_number present → native PostgREST upsert keyed
  // on the unique partial index `idx_orders_user_merchant_number_unique
  // (user_id, normalized_merchant, order_number) WHERE order_number IS
  // NOT NULL`. One round-trip; the index is the conflict target.
  if (order.order_number) {
    const row = {
      ...order,
      created_at: now,
      updated_at: now,
    };
    const { data, error } = await supabase
      .from('orders')
      .upsert([row], {
        onConflict: 'user_id,normalized_merchant,order_number',
        ignoreDuplicates: false,
      })
      .select('id')
      .single();
    if (error) throw new Error(`Failed to upsert order: ${error.message}`);
    // PostgREST doesn't tell us insert-vs-update; default to false (the
    // safer assumption — caller logs "updated existing" rather than
    // double-fire onboarding).
    return { id: data.id, isNew: false };
  }

  // Slow path: order_number is null. The partial unique index doesn't
  // cover this, so fall back to the legacy find-then-update-or-insert
  // pattern with the null-stripping update logic. We don't want to
  // clobber a good order_number from an earlier classification with a
  // null from a sibling email that didn't expose one.
  const { data: existing, error: findError } = await supabase
    .from('orders')
    .select('id')
    .eq('user_id', order.user_id)
    .eq('normalized_merchant', order.normalized_merchant)
    .is('order_number', null)
    .maybeSingle();

  if (findError) {
    throw new Error(`Failed to find existing order: ${findError.message}`);
  }

  const baseRecord = {
    ...order,
    updated_at: now,
    created_at: existing ? undefined : now,
  };

  if (existing) {
    // Strip null/undefined fields so a re-classification with a
    // missing value doesn't clobber a perfectly good earlier value.
    const updateRecord: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(baseRecord)) {
      if (value !== null && value !== undefined) updateRecord[key] = value;
    }
    // The classification trio is always authoritative when present — a
    // re-classification (e.g. digital→physical) must be able to CLEAR a
    // stale hidden_reason and flip hidden back, so these bypass the
    // null-strip above (a null hidden_reason here means "clear it").
    if (order.classification !== undefined) {
      updateRecord.classification = order.classification;
      updateRecord.hidden = order.hidden ?? false;
      updateRecord.hidden_reason = order.hidden_reason ?? null;
    }
    const { data, error } = await supabase
      .from('orders')
      .update(updateRecord)
      .eq('id', existing.id)
      .select('id')
      .single();
    if (error) throw new Error(`Failed to update order: ${error.message}`);
    return { id: data.id, isNew: false };
  }

  const { data, error } = await supabase
    .from('orders')
    .insert([baseRecord])
    .select('id')
    .single();

  if (error) throw new Error(`Failed to insert order: ${error.message}`);
  return { id: data.id, isNew: true };
}

/**
 * Get all orders for a user, optionally filtered by status.
 */
export async function getOrders(
  userId: string,
  options?: { status?: OrderStatus; limit?: number },
): Promise<OrderRecord[]> {
  let query = supabase
    .from('orders')
    .select('*')
    .eq('user_id', userId)
    .order('created_at', { ascending: false });

  if (options?.status) {
    query = query.eq('status', options.status);
  }

  if (options?.limit) {
    query = query.limit(options.limit);
  }

  const { data, error } = await query;
  if (error) throw new Error(`Failed to get orders: ${error.message}`);
  return data || [];
}

/**
 * Update order status based on derived shipment states.
 */
export async function updateOrderStatus(
  orderId: string,
  status: OrderStatus,
): Promise<void> {
  const { error } = await supabase
    .from('orders')
    .update({ status, updated_at: new Date().toISOString() })
    .eq('id', orderId);

  if (error) throw new Error(`Failed to update order status: ${error.message}`);
}

// ─── Shipment helpers ───────────────────────────────────────────────────────

/**
 * Upsert a shipment. Returns the shipment ID.
 *
 * Single-RT native PostgREST upsert keyed on the unique
 * `(order_id, tracking_number)` index. The previous "find by
 * tracking_number alone" approach (Round 4) was both 2-RT and a soft
 * cross-tenant bug: tracking numbers aren't globally unique per
 * carrier, so we'd occasionally pick someone else's shipment.
 *
 * `isNew` is intentionally `undefined` — PostgREST doesn't return
 * per-row insert-vs-update info, and adding a probe to populate it
 * for log lines pulled the path back to 2-RT (defeating the upsert
 * win). Callers that legitimately need the value should use raw SQL.
 */
export async function upsertShipment(
  shipment: Omit<ShipmentRecord, 'id' | 'created_at' | 'updated_at'>,
): Promise<{ id: string; isNew?: boolean }> {
  const now = new Date().toISOString();
  const row = { ...shipment, created_at: now, updated_at: now };

  const { data, error } = await supabase
    .from('shipments')
    .upsert([row], { onConflict: 'order_id,tracking_number', ignoreDuplicates: false })
    .select('id')
    .single();

  if (error) throw new Error(`Failed to upsert shipment: ${error.message}`);
  return { id: data.id };
}

/**
 * Get all shipments for an order.
 */
export async function getShipmentsForOrder(orderId: string): Promise<ShipmentRecord[]> {
  const { data, error } = await supabase
    .from('shipments')
    .select('*')
    .eq('order_id', orderId)
    .order('created_at', { ascending: true });

  if (error) throw new Error(`Failed to get shipments: ${error.message}`);
  return data || [];
}

/**
 * Get all undelivered shipments for a user (for 17track polling).
 *
 * The user filter is pushed into the query so PostgREST returns only
 * matching rows — previous version pulled ALL undelivered shipments
 * across every user and filtered in JS, which was an obvious cross-
 * tenant data exposure waiting to happen and a multi-MB payload at
 * scale.
 */
export async function getUndeliveredShipments(userId: string): Promise<Array<ShipmentRecord & { order: OrderRecord }>> {
  const { data, error } = await supabase
    .from('shipments')
    .select('*, orders!inner(*)')
    .eq('orders.user_id', userId)
    .neq('status', 'delivered')
    .order('created_at', { ascending: false });

  if (error) throw new Error(`Failed to get undelivered shipments: ${error.message}`);

  return (data || []) as Array<ShipmentRecord & { order: OrderRecord }>;
}

/**
 * Update shipment from 17track response.
 */
export async function updateShipmentFromTracker(
  shipmentId: string,
  trackerData: {
    status: ShipmentStatus;
    checkpoint?: string;
    shipped_at?: string;
    delivered_at?: string;
    /** Phase 1 ETA: optional eta triplet to write. Only set when the
     *  caller has resolved (via resolveETAUpdate) that the new ETA
     *  should overwrite the current one. */
    eta_at?: string;
    eta_source?: '17track' | 'email' | 'heuristic';
    eta_recorded_at?: string;
  },
): Promise<void> {
  const update: Record<string, unknown> = {
    status: trackerData.status,
    latest_checkpoint: trackerData.checkpoint || null,
    shipped_at: trackerData.shipped_at || null,
    delivered_at: trackerData.delivered_at || null,
    updated_at: new Date().toISOString(),
  };
  if (trackerData.eta_at !== undefined) update.eta_at = trackerData.eta_at;
  if (trackerData.eta_source !== undefined) update.eta_source = trackerData.eta_source;
  if (trackerData.eta_recorded_at !== undefined) update.eta_recorded_at = trackerData.eta_recorded_at;

  const { error } = await supabase
    .from('shipments')
    .update(update)
    .eq('id', shipmentId);

  if (error) throw new Error(`Failed to update shipment from tracker: ${error.message}`);
}

// ─── Review Item helpers ────────────────────────────────────────────────────

/**
 * Create a review item for ambiguous cases.
 */
export async function createReviewItem(
  item: Omit<ReviewItemRecord, 'id' | 'created_at' | 'updated_at'>,
): Promise<string> {
  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from('review_items')
    .insert([{ ...item, created_at: now, updated_at: now }])
    .select('id')
    .single();

  if (error) throw new Error(`Failed to create review item: ${error.message}`);
  return data.id;
}

/**
 * Get all unresolved review items for a user.
 */
export async function getUnresolvedReviewItems(
  userId: string,
): Promise<ReviewItemRecord[]> {
  const { data, error } = await supabase
    .from('review_items')
    .select('*')
    .eq('user_id', userId)
    .is('resolved_at', null)
    .order('created_at', { ascending: false });

  if (error) throw new Error(`Failed to get review items: ${error.message}`);
  return data || [];
}

/**
 * Resolve a review item.
 */
export async function resolveReviewItem(reviewItemId: string): Promise<void> {
  const { error } = await supabase
    .from('review_items')
    .update({ resolved_at: new Date().toISOString(), updated_at: new Date().toISOString() })
    .eq('id', reviewItemId);

  if (error) throw new Error(`Failed to resolve review item: ${error.message}`);
}

// ─── Derive order status from shipments ───────────────────────────────────

/**
 * Derive the best order status from its shipments.
 */
export function deriveOrderStatusFromShipments(
  shipments: ShipmentRecord[],
): OrderStatus {
  if (shipments.length === 0) return 'processing';

  const statuses = shipments.map(s => s.status);

  if (statuses.every(s => s === 'delivered')) return 'delivered';
  if (statuses.some(s => s === 'exception')) return 'issue';
  if (statuses.every(s => s === 'label_created' || s === 'unknown')) return 'ordered';
  if (statuses.some(s => s === 'out_for_delivery')) return 'shipped';
  if (statuses.some(s => s === 'in_transit')) return 'shipped';

  return 'ordered';
}

/**
 * Reconcile order + shipment state: link shipments to orders, create
 * review items for orphans.
 *
 * Single-query JOIN replaces the previous N+1 (one getShipmentsForOrder
 * call per order — 51 round-trips with 50 orders). PostgREST embeds
 * shipments via the FK, so we get all orders + their shipment counts
 * in one fetch.
 */
export async function reconcileOrderShipment(
  userId: string,
): Promise<{ linked: number; orphans: number }> {
  const { data, error } = await supabase
    .from('orders')
    .select('id, merchant_name, order_number, status, shipments(id)')
    .eq('user_id', userId);

  if (error) {
    throw new Error(`Failed to load orders+shipments for reconcile: ${error.message}`);
  }

  const orders = data ?? [];
  let orphans = 0;

  for (const order of orders) {
    const shipmentCount = Array.isArray((order as { shipments?: unknown[] }).shipments)
      ? ((order as { shipments: unknown[] }).shipments).length
      : 0;
    if (shipmentCount === 0 && order.status !== 'delivered' && order.status !== 'cancelled') {
      await createReviewItem({
        user_id: userId,
        type: 'order_no_shipment',
        related_order_id: order.id!,
        related_shipment_id: null,
        reason: `Order "${order.merchant_name}" (${order.order_number || 'no order number'}) has no linked shipments`,
        suggested_action: 'Link a tracking number or mark as cancelled if never shipped',
        confidence_score: 0.9,
        resolved_at: null,
      });
      orphans++;
    }
  }

  return { linked: orders.length - orphans, orphans };
}
