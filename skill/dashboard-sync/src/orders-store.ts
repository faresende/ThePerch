/**
 * orders-store.ts
 * Typed UPSERT helpers for orders, shipments, and review_items tables.
 */

import { supabase } from './supabase';

// ─── Types ──────────────────────────────────────────────────────────────────

export type OrderStatus =
  | 'ordered'
  | 'processing'
  | 'shipped_partial'
  | 'shipped'
  | 'delivered'
  | 'cancelled'
  | 'issue';

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
}

// ─── Order helpers ─────────────────────────────────────────────────────────

/**
 * Upsert an order. Returns the order ID.
 */
export async function upsertOrder(order: OrderRecord): Promise<{ id: string; isNew: boolean }> {
  // Try to find existing order by normalized_merchant + order_number
  let query = supabase
    .from('orders')
    .select('id')
    .eq('user_id', order.user_id)
    .eq('normalized_merchant', order.normalized_merchant);

  if (order.order_number) {
    query = query.eq('order_number', order.order_number);
  }

  const { data: existing, error: findError } = await query.maybeSingle();

  if (findError) {
    throw new Error(`Failed to find existing order: ${findError.message}`);
  }

  const now = new Date().toISOString();
  const baseRecord = {
    ...order,
    updated_at: now,
    created_at: existing ? undefined : now,
  };

  if (existing) {
    // Update path: strip null/undefined fields so a re-classification with
    // a missing value (e.g. order_number couldn't be re-extracted from a
    // sibling email) doesn't clobber a perfectly good earlier value.
    // Insert path keeps nulls — those are intentional empty fields.
    const updateRecord: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(baseRecord)) {
      if (value !== null && value !== undefined) updateRecord[key] = value;
    }
    const { data, error } = await supabase
      .from('orders')
      .update(updateRecord)
      .eq('id', existing.id)
      .select('id')
      .single();

    if (error) throw new Error(`Failed to update order: ${error.message}`);
    return { id: data.id, isNew: false };
  } else {
    const { data, error } = await supabase
      .from('orders')
      .insert([baseRecord])
      .select('id')
      .single();

    if (error) throw new Error(`Failed to insert order: ${error.message}`);
    return { id: data.id, isNew: true };
  }
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
 */
export async function upsertShipment(
  shipment: Omit<ShipmentRecord, 'id' | 'created_at' | 'updated_at'>,
): Promise<{ id: string; isNew: boolean }> {
  // Find existing by tracking number
  const { data: existing, error: findError } = await supabase
    .from('shipments')
    .select('id')
    .eq('tracking_number', shipment.tracking_number)
    .maybeSingle();

  if (findError) {
    throw new Error(`Failed to find existing shipment: ${findError.message}`);
  }

  const now = new Date().toISOString();

  if (existing) {
    const { data, error } = await supabase
      .from('shipments')
      .update({ ...shipment, updated_at: now })
      .eq('id', existing.id)
      .select('id')
      .single();

    if (error) throw new Error(`Failed to update shipment: ${error.message}`);
    return { id: data.id, isNew: false };
  } else {
    const { data, error } = await supabase
      .from('shipments')
      .insert([{ ...shipment, created_at: now, updated_at: now }])
      .select('id')
      .single();

    if (error) throw new Error(`Failed to insert shipment: ${error.message}`);
    return { id: data.id, isNew: true };
  }
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
 */
export async function getUndeliveredShipments(userId: string): Promise<Array<ShipmentRecord & { order: OrderRecord }>> {
  const { data, error } = await supabase
    .from('shipments')
    .select('*, orders(*)')
    .neq('status', 'delivered')
    .order('created_at', { ascending: false });

  if (error) throw new Error(`Failed to get undelivered shipments: ${error.message}`);

  // Filter to only user's shipments
  return (data || []).filter(
    (s: any) => s.orders && (s.orders as OrderRecord).user_id === userId,
  ) as Array<ShipmentRecord & { order: OrderRecord }>;
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
  },
): Promise<void> {
  const { error } = await supabase
    .from('shipments')
    .update({
      status: trackerData.status,
      latest_checkpoint: trackerData.checkpoint || null,
      shipped_at: trackerData.shipped_at || null,
      delivered_at: trackerData.delivered_at || null,
      updated_at: new Date().toISOString(),
    })
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
 * Reconcile order + shipment state: link shipments to orders, create review items for orphans.
 */
export async function reconcileOrderShipment(
  userId: string,
): Promise<{ linked: number; orphans: number }> {
  // Find all orders with no shipments
  const orders = await getOrders(userId);
  let orphans = 0;

  for (const order of orders) {
    const shipments = await getShipmentsForOrder(order.id!);
    if (shipments.length === 0 && order.status !== 'delivered' && order.status !== 'cancelled') {
      // Order has no shipments — create review item
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
