/**
 * orders-autopilot.ts
 * Main pipeline: classify email → extract → match → upsert → derive status → push to iOS
 *
 * Exposes two tools:
 *   processEmail(email)    — process a single email through the full pipeline
 *   pollShipments(userId) — poll 17track for all undelivered shipments
 */

import { supabase } from './supabase';
import {
  classifyEmail,
  extractOrderFields,
  extractShipmentFields,
  EmailType,
} from './email-classifier';
import {
  upsertOrder,
  upsertShipment,
  createReviewItem,
  getShipmentsForOrder,
  getUndeliveredShipments,
  updateOrderStatus,
  updateShipmentFromTracker,
  deriveOrderStatusFromShipments,
  carrierTrackingURL,
  OrderRecord,
  ShipmentRecord,
} from './orders-store';
import {
  pollTrackingNumbers,
  normalizeCarrierForTracker,
  pollSingleShipment,
  TrackerResponse,
} from './seventeen-track';

// ─── Interfaces ─────────────────────────────────────────────────────────────

export interface EmailInput {
  id: string;           // Gmail message ID
  subject: string;
  body: string;         // Plain text body
  sender: string;        // From address
  date: string;         // RFC 3339 date
}

export interface ProcessEmailResult {
  success: boolean;
  type: EmailType;
  action: 'created_order' | 'linked_shipment' | 'created_review_item' | 'skipped' | 'error';
  detail: string;
  confidence: number;
}

// ─── Constants ─────────────────────────────────────────────────────────────

const SEVENTEEN_TRACK_API_KEY = process.env.SEVENTEEN_TRACK_API_KEY || '';

// ─── Main pipeline: processEmail ───────────────────────────────────────────

/**
 * Process a single email through the full Orders Autopilot pipeline.
 *
 * Steps:
 * 1. Classify: purchase_confirmation vs shipping_notification vs other
 * 2. Extract: pull order or shipment fields
 * 3. Match: link shipment to order via tracking number or merchant+number
 * 4. Upsert: write to orders/shipments tables
 * 5. Derive: update order status based on shipment state
 * 6. Push: write commerce record to dashboard_records for iOS
 */
export async function processEmail(email: EmailInput): Promise<ProcessEmailResult> {
  const { id, subject, body, sender, date } = email;

  try {
    // Step 1: Classify
    const { type, confidence } = classifyEmail(subject, body, sender);

    if (type === 'other') {
      return {
        success: true,
        type,
        action: 'skipped',
        detail: 'Email does not appear to be purchase or shipping related',
        confidence,
      };
    }

    // Step 2: Extract
    if (type === 'purchase_confirmation') {
      return await handlePurchaseConfirmation(email, confidence);
    } else if (type === 'shipping_notification') {
      return await handleShippingNotification(email, confidence);
    }

    return { success: true, type, action: 'skipped', detail: 'Unknown type', confidence };

  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[orders-autopilot] processEmail error for ${id}:`, message);
    return {
      success: false,
      type: 'other',
      action: 'error',
      detail: message,
      confidence: 0,
    };
  }
}

// ─── Purchase confirmation handler ─────────────────────────────────────────

async function handlePurchaseConfirmation(
  email: EmailInput,
  baseConfidence: number,
): Promise<ProcessEmailResult> {
  const { id, sender, date } = email;

  const fields = extractOrderFields(email.subject, email.body, sender, id);

  if (!fields.merchantName || fields.merchantName === 'Unknown') {
    return {
      success: false,
      type: 'purchase_confirmation',
      action: 'error',
      detail: 'Could not identify merchant from email',
      confidence: baseConfidence,
    };
  }

  // Upsert order
  const { id: orderId, isNew } = await upsertOrder({
    user_id: await getUserIdFromEmail(sender),
    merchant_name: fields.merchantName,
    normalized_merchant: fields.normalizedMerchant,
    order_number: fields.orderNumber,
    order_date: fields.orderDate ? new Date(fields.orderDate).toISOString() : null,
    total_amount: fields.totalAmount,
    currency: fields.currency,
    source_email_ids: [id],
    confidence_score: baseConfidence,
    status: 'ordered',
  });

  // Push to iOS via dashboard_records with category=commerce
  await pushCommerceRecord(orderId, 'order', fields, baseConfidence);

  return {
    success: true,
    type: 'purchase_confirmation',
    action: isNew ? 'created_order' : 'created_order',
    detail: `${isNew ? 'Created' : 'Updated'} order: ${fields.merchantName}${fields.orderNumber ? ` #${fields.orderNumber}` : ''}`,
    confidence: baseConfidence,
  };
}

// ─── Shipping notification handler ─────────────────────────────────────────

async function handleShippingNotification(
  email: EmailInput,
  baseConfidence: number,
): Promise<ProcessEmailResult> {
  const { id, sender } = email;

  const fields = extractShipmentFields(email.subject, email.body, sender, id);

  if (!fields.trackingNumber) {
    // No tracking number found — create a review item instead
    await createReviewItem({
      user_id: await getUserIdFromEmail(sender),
      type: 'orphan_shipment',
      related_order_id: null,
      related_shipment_id: null,
      reason: `Shipping notification email from ${sender} but no tracking number could be extracted`,
      suggested_action: 'Review the email and manually add tracking number if valid',
      confidence_score: baseConfidence * 0.5,
    });

    return {
      success: true,
      type: 'shipping_notification',
      action: 'created_review_item',
      detail: 'No tracking number found — created review item for manual review',
      confidence: baseConfidence,
    };
  }

  // Try to find matching order via tracking number or merchant
  const userId = await getUserIdFromEmail(sender);

  // Try to find order by tracking number first
  const { data: existingByTracking } = await supabase
    .from('shipments')
    .select('order_id')
    .eq('tracking_number', fields.trackingNumber)
    .maybeSingle();

  if (existingByTracking) {
    // Shipment already linked to an order
    return {
      success: true,
      type: 'shipping_notification',
      action: 'skipped',
      detail: `Tracking ${fields.trackingNumber} already linked to an order`,
      confidence: baseConfidence,
    };
  }

  // Try to link to an existing order via merchant
  const merchantName = extractOrderFields(email.subject, email.body, sender, id).merchantName;
  const normalizedMerchant = merchantName?.toLowerCase().replace(/[^a-z0-9]/g, '') || '';

  let orderId: string | null = null;
  if (normalizedMerchant) {
    const { data: existingOrder } = await supabase
      .from('orders')
      .select('id')
      .eq('user_id', userId)
      .eq('normalized_merchant', normalizedMerchant)
      .in('status', ['ordered', 'processing', 'shipped_partial'])
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    orderId = existingOrder?.id || null;
  }

  if (!orderId) {
    // Could not find matching order — create review item
    await createReviewItem({
      user_id: userId,
      type: 'shipment_no_order',
      related_order_id: null,
      related_shipment_id: null,
      reason: `Shipment with tracking ${fields.trackingNumber} (${fields.carrier || 'unknown carrier'}) could not be matched to any order`,
      suggested_action: 'Link this shipment to the correct order or mark as standalone',
      confidence_score: baseConfidence * 0.6,
    });

    return {
      success: true,
      type: 'shipping_notification',
      action: 'created_review_item',
      detail: `Tracking ${fields.trackingNumber} could not be matched to an order — created review item`,
      confidence: baseConfidence,
    };
  }

  // Upsert shipment linked to order
  const { id: shipmentId } = await upsertShipment({
    order_id: orderId,
    tracking_number: fields.trackingNumber,
    carrier: fields.carrier,
    tracking_url: carrierTrackingURL(fields.carrier, fields.trackingNumber),
    seventeen_track_id: null,
    status: fields.status as any,
    latest_checkpoint: fields.status === 'in_transit' ? `Status: ${fields.status}` : null,
    shipped_at: fields.shippedAt ? new Date(fields.shippedAt).toISOString() : null,
    delivered_at: fields.status === 'delivered' ? new Date().toISOString() : null,
    source_email_ids: [id],
    confidence_score: baseConfidence,
  });

  // Derive and update order status
  const shipments = await getShipmentsForOrder(orderId);
  const newStatus = deriveOrderStatusFromShipments(shipments);
  await updateOrderStatus(orderId, newStatus);

  // Push updated status to iOS
  const { data: updatedOrder } = await supabase
    .from('orders')
    .select('*')
    .eq('id', orderId)
    .single();

  if (updatedOrder) {
    await pushCommerceRecord(orderId, 'order', updatedOrder as any, baseConfidence);
  }

  // If 17track API key is available, immediately poll for latest status
  if (SEVENTEEN_TRACK_API_KEY && fields.trackingNumber) {
    // Fire and forget — update will happen on next poll cycle
    pollAndUpdateShipment(SEVENTEEN_TRACK_API_KEY, shipmentId, fields.trackingNumber, fields.carrier)
      .catch(err => console.warn('[orders-autopilot] 17track poll failed:', err.message));
  }

  return {
    success: true,
    type: 'shipping_notification',
    action: 'linked_shipment',
    detail: `Linked tracking ${fields.trackingNumber} to order`,
    confidence: baseConfidence,
  };
}

// ─── 17track polling ───────────────────────────────────────────────────────

/**
 * Poll 17track for all undelivered shipments of a user.
 */
export async function pollShipments(userId: string): Promise<{
  updated: number;
  errors: string[];
}> {
  if (!SEVENTEEN_TRACK_API_KEY) {
    return { updated: 0, errors: ['SEVENTEEN_TRACK_API_KEY not set'] };
  }

  const undelivered = await getUndeliveredShipments(userId);

  if (undelivered.length === 0) {
    return { updated: 0, errors: [] };
  }

  // Register all tracking numbers first (17track requires this)
  const toRegister = undelivered.map(s => ({
    number: s.tracking_number,
    carrier: s.carrier ? normalizeCarrierForTracker(s.carrier) : 'unknown',
  }));

  try {
    await pollTrackingNumbers(SEVENTEEN_TRACK_API_KEY, toRegister.map(t => t.number));
  } catch (err) {
    return { updated: 0, errors: [(err as Error).message] };
  }

  // Poll for all
  const trackingNumbers = undelivered.map(s => s.tracking_number);
  const results: TrackerResponse[] = [];

  try {
    const polled = await pollTrackingNumbers(SEVENTEEN_TRACK_API_KEY, trackingNumbers);
    results.push(...polled);
  } catch (err) {
    return { updated: 0, errors: [(err as Error).message] };
  }

  const resultsMap = new Map(results.map(r => [r.tracking_number, r]));

  let updated = 0;
  const errors: string[] = [];

  for (const shipment of undelivered) {
    const trackerData = resultsMap.get(shipment.tracking_number);
    if (!trackerData) continue;

    try {
      await updateShipmentFromTracker(shipment.id!, {
        status: trackerData.status,
        checkpoint: trackerData.latest_checkpoint || undefined,
        shipped_at: trackerData.shipped_at || undefined,
        delivered_at: trackerData.delivered_at || undefined,
      });

      // Update order status after shipment update
      const shipments = await getShipmentsForOrder(shipment.order_id);
      const newOrderStatus = deriveOrderStatusFromShipments(shipments);
      await updateOrderStatus(shipment.order_id, newOrderStatus);

      updated++;
    } catch (err) {
      errors.push(`${shipment.tracking_number}: ${(err as Error).message}`);
    }
  }

  return { updated, errors };
}

async function pollAndUpdateShipment(
  apiKey: string,
  shipmentId: string,
  trackingNumber: string,
  carrier: string | null,
): Promise<void> {
  const result = await pollSingleShipment(apiKey, trackingNumber, carrier || undefined);

  await updateShipmentFromTracker(shipmentId, {
    status: result.status,
    checkpoint: result.latest_checkpoint || undefined,
    shipped_at: result.shipped_at || undefined,
    delivered_at: result.delivered_at || undefined,
  });
}

// ─── Push to iOS ───────────────────────────────────────────────────────────

/**
 * Push an order or shipment record to dashboard_records with category='commerce'.
 * This makes it visible in the iOS app's OrdersView.
 */
async function pushCommerceRecord(
  entityId: string,
  entityType: 'order' | 'shipment',
  data: any,
  confidence: number,
): Promise<void> {
  const now = new Date().toISOString();

  if (entityType === 'order') {
    const orderData = data;
    await supabase.from('dashboard_records').upsert([{
      agent_id: 'entregas',
      title: orderData.merchant_name,
      type: 'measurement', // Reuse existing type for now
      category: 'deliveries',
      display_hint: 'status_list',
      pinned: false,
      data: {
        record_type: 'order',
        order_id: entityId,
        merchant_name: orderData.merchant_name,
        order_number: orderData.order_number,
        total_amount: orderData.total_amount,
        currency: orderData.currency,
        status: orderData.status,
        confidence_score: orderData.confidence_score,
        created_at: orderData.created_at,
      },
      updated_at: now,
    }], {
      onConflict: 'agent_id,category,title',
    });
  }
}

// ─── Helpers ───────────────────────────────────────────────────────────────

/**
 * Get user ID from sender email.
 * Currently uses a simple lookup — in production this would query the users table.
 */
async function getUserIdFromEmail(senderEmail: string): Promise<string> {
  // FABIO_HARDCODED for now — in production this would be a proper user lookup
  const FABIO_USER_ID = '00000000-0000-0000-0000-000000000000';

  const { data, error } = await supabase
    .from('users')
    .select('id')
    .eq('email', senderEmail.toLowerCase())
    .maybeSingle();

  if (error) {
    console.warn(`[orders-autopilot] User lookup failed for ${senderEmail}, using hardcoded Fabio:`, error.message);
    return FABIO_USER_ID;
  }

  return data?.id || FABIO_USER_ID;
}

// ─── Tool wrappers for OpenClaw ────────────────────────────────────────────

export const tools = {
  processEmail: async (email: EmailInput) => {
    return processEmail(email);
  },

  pollShipments: async (userId: string) => {
    return pollShipments(userId);
  },
};

export default tools;
