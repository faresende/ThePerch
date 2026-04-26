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
import { extractWithLLM, LLMExtractedFields } from './llm-extractor';
import {
  lookupLearnedSender,
  recordLearnedSender,
  LearnedSenderMatch,
} from './learned-senders';
import {
  registerTrackingNumbers,
  pollTrackingNumbers,
  normalizeCarrierForTracker,
  pollSingleShipment,
  TrackerResponse,
} from './seventeen-track';

// ─── Interfaces ─────────────────────────────────────────────────────────────

export interface EmailInput {
  id: string;           // JMAP / Gmail message ID
  subject: string;
  body: string;         // Plain text body
  sender: string;       // From address (legacy: "Name <email>" or just "email")
  senderName?: string;  // Optional display name from `From:` header
  senderEmail?: string; // Optional bare email when listener provides them split
  folders?: string[];   // Optional list of folder/label names the email is in
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

  // Normalize sender into bare email + display name. Listener may pass
  // them split (preferred), or a legacy "Name <email>" string, or just
  // a bare address.
  const senderEmail = (email.senderEmail
    || (sender.match(/<([^>]+)>/)?.[1])
    || sender).trim().toLowerCase();
  const senderName = (email.senderName
    || (sender.match(/^([^<]+)</)?.[1])
    || '').trim();

  try {
    // Tier 3 pre-fetch: consult the learned_senders table BEFORE
    // classification. A hit here means the user has previously resolved
    // a review_item with (sender → merchant), so we both:
    //   1. Boost the purchase signal in classifyEmail (a learned sender
    //      with even a moderate purchase score should land in orders),
    //      and
    //   2. Pin the merchant name to the user-taught value so neither the
    //      hardcoded list nor the LLM can second-guess it.
    // A miss is silent — caller falls back to keyword/LLM logic.
    let learned: LearnedSenderMatch | null = null;
    try {
      const userId = await getUserIdFromEmail(senderEmail);
      learned = await lookupLearnedSender(userId, senderEmail);
    } catch (err) {
      // Lookup is best-effort. PERCH_USER_ID may be missing in tests;
      // don't break the pipeline over a learned-sender miss.
      console.warn('[orders-autopilot] learned_senders lookup skipped:', (err as Error).message);
    }

    // Step 1: Classify
    const { type, confidence } = classifyEmail(subject, body, senderEmail, {
      senderName,
      folders: email.folders ?? [],
      hasLearnedSender: !!learned,
    });

    if (type === 'other') {
      // Tier 2 LLM second-pass: if there's meaningful commerce signal
      // (confidence ≥ 0.4) we ask the LLM whether this is actually an
      // order. The LLM is good at the long tail of phrasings keyword
      // matching can't catch ("Your trip is booked", "Pre-order
      // received", non-English subjects, etc.).
      if (confidence >= 0.4) {
        const llm = await extractWithLLM(subject, senderEmail, body);
        if (llm && llm.is_purchase_confirmation && llm.confidence >= 0.6) {
          // Promote to purchase path with LLM-provided fields.
          return await handlePurchaseConfirmation(email, llm.confidence, llm, learned);
        }
        // LLM agrees it's not an order, OR LLM unreachable — but the
        // ambiguity is real. Queue for review instead of silently
        // dropping; the iOS review queue (Tier 3) will surface it.
        try {
          await createReviewItem({
            user_id: await getUserIdFromEmail(senderEmail),
            type: 'other',
            related_order_id: null,
            related_shipment_id: null,
            reason: `Ambiguous classification (regex confidence ${confidence.toFixed(2)}${llm ? `, LLM said ${llm.is_purchase_confirmation ? 'purchase' : 'not purchase'} @ ${llm.confidence.toFixed(2)}` : ', LLM unreachable'}): "${subject.slice(0, 80)}" from ${senderEmail}`,
            suggested_action: 'Review manually — classifier unsure if this is an order',
            confidence_score: confidence,
          });
          return { success: true, type, action: 'created_review_item', detail: `Queued for review (confidence ${confidence.toFixed(2)})`, confidence };
        } catch (e) {
          // If review_item insert fails, fall through to the legacy skip.
        }
      }
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
      return await handlePurchaseConfirmation(email, confidence, undefined, learned);
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
  preExtractedLLM?: LLMExtractedFields | null,
  learned?: LearnedSenderMatch | null,
): Promise<ProcessEmailResult> {
  const { id, sender, date } = email;

  // Reuse the same email→display-name parsing as the top-level entry.
  const senderEmail = (email.senderEmail
    || (sender.match(/<([^>]+)>/)?.[1])
    || sender).trim().toLowerCase();
  const senderName = (email.senderName
    || (sender.match(/^([^<]+)</)?.[1])
    || '').trim();

  const regexFields = extractOrderFields(
    email.subject,
    email.body,
    senderEmail,
    id,
    senderName,
    learned?.merchant_name,
  );

  // Decide whether we need the LLM. Cases:
  //   a) the caller already ran it (Tier 1 said "other", LLM disagreed
  //      → reuse those fields).
  //   b) regex merchant came from the weak `domainStem` last-resort
  //      branch — inferMerchantName couldn't find anything better than
  //      the bare sender domain.
  //   c) regex didn't find an order_number despite the strong "order
  //      ... confirmed" signal that got us here.
  // Critically, a `learnedSender` / `known` / `displayName` /
  // `shopifyBody` / `subject` merchant resolution is trusted — we don't
  // call the LLM just to second-guess them on the merchant axis. The
  // LLM may still fire to recover an order_number in case (c), but the
  // merge logic below pins the merchant when the source is high-trust.
  const needsLLM = !preExtractedLLM
    && (regexFields.merchantSource === 'domainStem'
        || (!regexFields.orderNumber && /order/i.test(email.subject)));

  let llm: LLMExtractedFields | null = preExtractedLLM ?? null;
  if (needsLLM) {
    llm = await extractWithLLM(email.subject, senderEmail, email.body);
  }

  // Merchant name lock: a learned-sender or hardcoded-known mapping is
  // never overridden by the LLM. Both sources represent explicit
  // ground-truth (user or engineering); LLM output is best-treated as a
  // last-resort fallback for the weak `domainStem` path.
  const merchantNameLocked =
    regexFields.merchantSource === 'learnedSender'
    || regexFields.merchantSource === 'known';

  // Merge: LLM wins on disputes for merchant + order_number + total when
  // it's confident. Regex wins otherwise (fast + cheap, already validated).
  const mergedMerchantName = merchantNameLocked
    ? regexFields.merchantName
    : (llm && llm.confidence >= 0.6 && llm.merchant_name)
        ? llm.merchant_name
        : regexFields.merchantName;
  const mergedOrderNumber = (llm && llm.confidence >= 0.6 && llm.order_number)
    ? llm.order_number.replace(/^#/, '')
    : regexFields.orderNumber;
  const mergedTotal = (llm && llm.confidence >= 0.6 && typeof llm.total_amount === 'number')
    ? llm.total_amount
    : regexFields.totalAmount;
  const mergedCurrency = (llm && llm.confidence >= 0.6 && llm.currency)
    ? llm.currency
    : regexFields.currency;

  const fields = {
    ...regexFields,
    merchantName: mergedMerchantName,
    normalizedMerchant: mergedMerchantName.toLowerCase().replace(/[^a-z0-9]/g, ''),
    orderNumber: mergedOrderNumber,
    totalAmount: mergedTotal,
    currency: mergedCurrency,
  };

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

  // Filter out malformed tracking numbers before sending to 17track.
  // A malformed entry in the batch (e.g. "7197712620 / 001959496839433548"
  // from a multi-carrier email) rejects the whole request with -18010013.
  const isValidTrackingNumber = (n: string | null | undefined): n is string =>
    typeof n === 'string'
    && n.length >= 6
    && n.length <= 40
    && !/[\s,/\\]/.test(n);

  // Register all tracking numbers first (17track requires this before it
  // will return tracking info). Registration is idempotent — 17track
  // silently skips numbers already on the account.
  const toRegister = undelivered
    .filter(s => isValidTrackingNumber(s.tracking_number))
    .map(s => ({
      number: s.tracking_number,
      ...(s.carrier ? { carrier: normalizeCarrierForTracker(s.carrier) || undefined } : {}),
    }));

  if (toRegister.length === 0) {
    return { updated: 0, errors: ['no valid tracking numbers to poll'] };
  }

  try {
    await registerTrackingNumbers(SEVENTEEN_TRACK_API_KEY, toRegister);
  } catch (err) {
    return { updated: 0, errors: [(err as Error).message] };
  }

  // Poll for all (same filter as register).
  const trackingNumbers = undelivered
    .map(s => s.tracking_number)
    .filter(isValidTrackingNumber);
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
 * Resolve the user this email belongs to.
 *
 * In the current single-user deployment, `PERCH_USER_ID` is authoritative —
 * every inbound email belongs to the installed user. A future multi-tenant
 * deployment should reintroduce a sender → user lookup here (the previous
 * `users.email` query was removed because the `public.users` table does not
 * carry an email column; ownership is managed via `auth.users`).
 *
 * The `senderEmail` argument is retained for a future multi-tenant path and
 * for logging, but is not consulted today.
 */
async function getUserIdFromEmail(_senderEmail: string): Promise<string> {
  const resolved = process.env.PERCH_USER_ID;
  if (!resolved) {
    throw new Error(
      'orders-autopilot: PERCH_USER_ID is not set. Export it in your agent env '
      + 'or source it from ~/.openclaw/secrets/perch.env before running.'
    );
  }
  return resolved;
}

// ─── Review-queue resolution (Tier 3 write-back) ───────────────────────────

/**
 * Called by the iOS review-queue UI (Settings → Order Review) when the
 * user confirms a (sender → merchant) mapping for a queued review_item.
 *
 * Writes:
 *   1. the sender→merchant mapping into `learned_senders` (so the next
 *      email from this sender skips the review queue), and
 *   2. (optional) creates / updates an order row from the user-confirmed
 *      fields, and
 *   3. resolves the source review_item.
 *
 * The order-row creation is the iOS-side responsibility for now — this
 * function only handles the learned_senders write-back + review-item
 * resolution. We expose the `recordLearnedSender` primitive directly so
 * the iOS layer can opt into either step independently.
 */
export async function resolveReviewWithLearnedSender(args: {
  userId: string;
  reviewItemId: string;
  senderEmail: string;
  merchantName: string;
  learnedFromEmailId?: string | null;
}): Promise<{ learnedSenderId: string }> {
  const learnedSenderId = await recordLearnedSender({
    userId: args.userId,
    senderEmail: args.senderEmail,
    merchantName: args.merchantName,
    learnedFromEmailId: args.learnedFromEmailId ?? null,
    learnedFromReviewItemId: args.reviewItemId,
  });

  // Mark the review item resolved. Done inline here (instead of importing
  // resolveReviewItem) so the autopilot owns the full transaction shape.
  const { error } = await supabase
    .from('review_items')
    .update({ resolved_at: new Date().toISOString(), updated_at: new Date().toISOString() })
    .eq('id', args.reviewItemId)
    .eq('user_id', args.userId);
  if (error) {
    console.warn(`[orders-autopilot] failed to resolve review_item ${args.reviewItemId}: ${error.message}`);
  }

  return { learnedSenderId };
}

// ─── Tool wrappers for OpenClaw ────────────────────────────────────────────

export const tools = {
  processEmail: async (email: EmailInput) => {
    return processEmail(email);
  },

  pollShipments: async (userId: string) => {
    return pollShipments(userId);
  },

  resolveReviewWithLearnedSender,
};

export default tools;
