/**
 * orders-autopilot.ts
 * Main pipeline: classify email → extract → match → upsert → derive status → push to iOS
 *
 * Exposes two tools:
 *   processEmail(email)    — process a single email through the full pipeline
 *   pollShipments(userId) — poll 17track for all undelivered shipments
 */

import { spawn } from 'node:child_process';
import { supabase } from './supabase';
import {
  classifyEmail,
  extractOrderFields,
  extractShipmentFields,
  senderIsCarrier,
  inferMerchantNameFromBody,
  cleanDisplayName,
  normalizeMerchant,
  EmailType,
} from './email-classifier';
import { searchEmailsByText, EmailMeta } from './jmap-search';
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
  replaceOrderItems,
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
  recordClassification,
  ClassificationLog,
} from './classifications-store';
import {
  registerTrackingNumbers,
  pollTrackingNumbers,
  normalizeCarrierForTracker,
  pollSingleShipment,
  TrackerResponse,
} from './seventeen-track';
import { ParseTraceBuilder } from './parse-trace';
import { detectPhysicalVsDigital } from './physical-vs-digital';
import { detectQuotedPriorOrder } from './quoted-prior-order';
import { pickETA } from './extract-eta';
import { resolveETAUpdate } from './resolve-eta';

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

  // Telemetry accumulator: every exit from this function (and its handlers)
  // writes ONE row to email_classifications via writeTelemetry. The base
  // payload is built up as we collect signals; handlers extend it before
  // their own exit.
  let userIdForTelemetry: string | null = null;
  try {
    userIdForTelemetry = await getUserIdFromEmail(senderEmail);
  } catch { /* PERCH_USER_ID missing — telemetry will silently skip */ }
  const telemetry: Partial<ClassificationLog> = {
    user_id: userIdForTelemetry ?? '',
    email_id: id,
    subject: subject?.slice(0, 500) ?? null,
    sender_email: senderEmail || null,
    sender_name: senderName || null,
    llm_called: false,
    learned_sender_matched: false,
  };

  // Phase-1 parse-trace accumulator. Lives alongside `telemetry` (which
  // writes one row per email to `email_classifications` for cross-row
  // analytics). The tracer's `build()` output is denormalized onto
  // each order row at upsert time as `orders.parse_trace`, giving iOS
  // an answer to "why did this get classified as an order?" without
  // an extra join.
  const tracer = new ParseTraceBuilder(id);

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
    if (learned) {
      telemetry.learned_sender_matched = true;
      telemetry.learned_sender_match_axis = learned.matched_on;
      tracer.recordLearnedSender({
        matched: true,
        match_axis: learned.matched_on,
        merchant: learned.merchant_name ?? null,
      });
    }

    // Phase-1 short-circuit: detect Topfoams-style replies that quote a
    // prior order. Runs BEFORE the classifier because tier1+LLM both
    // see the quoted "Order #X" as a strong purchase signal and would
    // create a duplicate. We need to bail out before they fire.
    //
    // Best-effort: if the user-id lookup fails (test harness without
    // PERCH_USER_ID) or the merchant can't be inferred yet, we skip
    // the check and fall through. False-negative cost is duplicating
    // a row the user can swipe-correct; false-positive cost would be
    // dropping a legitimate order, so we err on the side of caution.
    try {
      if (userIdForTelemetry) {
        const inferredMerchant = inferMerchantNameFromBody(body) || senderName || null;
        const normalizedMerchant = inferredMerchant
          ? normalizeMerchant(inferredMerchant)
          : null;
        const quoted = await detectQuotedPriorOrder({
          subject,
          body,
          userId: userIdForTelemetry,
          normalizedMerchant,
          supabase,
        });
        if (quoted.matched) {
          tracer.recordShortCircuit('quoted_prior_order');
          // We still log the short-circuit to telemetry so the rule
          // engine can later distill "Re: from this sender quoting
          // their own order#" into a merchant-rules pre-classifier.
          await writeTelemetry(telemetry, 'skipped',
            `Quoted prior order #${quoted.matched_order_number} — likely a CS reply, not a new order`);
          return {
            success: true,
            type: 'other',
            action: 'skipped',
            detail: `Reply quotes existing order #${quoted.matched_order_number}`,
            confidence: 0,
          };
        }
      }
    } catch (err) {
      console.warn('[orders-autopilot] quoted-prior-order check skipped:', (err as Error).message);
    }

    // Step 1: Classify
    const classified = classifyEmail(subject, body, senderEmail, {
      senderName,
      folders: email.folders ?? [],
      hasLearnedSender: !!learned,
    });
    const { type, confidence } = classified;
    telemetry.tier1_purchase_score = classified.purchaseScore;
    telemetry.tier1_shipping_score = classified.shippingScore;
    telemetry.tier1_type = type;
    telemetry.tier1_confidence = confidence;
    telemetry.tier1_matched_keywords = classified.matchedKeywords;
    tracer.recordTier1({
      matched_keywords: classified.matchedKeywords ?? [],
      confidence,
      purchase_score: classified.purchaseScore,
      shipping_score: classified.shippingScore,
    });

    if (type === 'other') {
      // Tier 2 LLM second-pass: if there's meaningful commerce signal
      // (confidence ≥ 0.4) we ask the LLM whether this is actually an
      // order. The LLM is good at the long tail of phrasings keyword
      // matching can't catch ("Your trip is booked", "Pre-order
      // received", non-English subjects, etc.).
      if (confidence >= 0.4) {
        telemetry.llm_called = true;
        const llm = await extractWithLLM(subject, senderEmail, body);
        if (llm) {
          telemetry.llm_provider = llm.source;
          telemetry.llm_is_purchase = llm.is_purchase_confirmation;
          telemetry.llm_confidence = llm.confidence;
          telemetry.llm_merchant_name = llm.merchant_name ?? null;
          telemetry.llm_order_number = llm.order_number ?? null;
          tracer.recordLLM({
            invoked: true,
            is_purchase: llm.is_purchase_confirmation,
            confidence: llm.confidence,
            provider: llm.source ?? null,
          });
        } else {
          telemetry.llm_provider = 'failed';
          tracer.recordLLM({ invoked: true, is_purchase: null, confidence: null, provider: 'failed' });
        }
        if (llm && llm.is_purchase_confirmation && llm.confidence >= 0.6) {
          // Promote to purchase path with LLM-provided fields.
          return await handlePurchaseConfirmation(email, llm.confidence, llm, learned, telemetry, tracer);
        }
        // LLM agrees it's not an order, OR LLM unreachable — but the
        // ambiguity is real. Queue for review instead of silently
        // dropping; the iOS review queue (Tier 3) will surface it.
        try {
          const reviewId = await createReviewItem({
            user_id: await getUserIdFromEmail(senderEmail),
            type: 'other',
            related_order_id: null,
            related_shipment_id: null,
            reason: `Ambiguous classification (regex confidence ${confidence.toFixed(2)}${llm ? `, LLM said ${llm.is_purchase_confirmation ? 'purchase' : 'not purchase'} @ ${llm.confidence.toFixed(2)}` : ', LLM unreachable'}): "${subject.slice(0, 80)}" from ${senderEmail}`,
            suggested_action: 'Review manually — classifier unsure if this is an order',
            confidence_score: confidence,

            // Structured fields the iOS review queue uses to render rows
            // and pre-fill the "Confirm as order" form. The autopilot's
            // best guesses (LLM-extracted if available, otherwise
            // sender-display-name as a fallback merchant).
            source_email_id: id,
            source_subject: subject?.slice(0, 500) ?? null,
            source_sender_email: senderEmail,
            source_sender_name: senderName || null,
            suggested_merchant: llm?.merchant_name ?? senderName ?? null,
            suggested_order_number: llm?.order_number ?? null,
            suggested_total_amount: typeof llm?.total_amount === 'number' ? llm.total_amount : null,
            suggested_currency: llm?.currency ?? null,
          });
          telemetry.related_review_item_id = reviewId;
          await writeTelemetry(telemetry, 'created_review_item', `Queued for review (confidence ${confidence.toFixed(2)})`);
          return { success: true, type, action: 'created_review_item', detail: `Queued for review (confidence ${confidence.toFixed(2)})`, confidence };
        } catch (e) {
          // If review_item insert fails, fall through to the legacy skip.
        }
      }
      await writeTelemetry(telemetry, 'skipped', 'Email does not appear to be purchase or shipping related');
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
      return await handlePurchaseConfirmation(email, confidence, undefined, learned, telemetry, tracer);
    } else if (type === 'shipping_notification') {
      return await handleShippingNotification(email, confidence, telemetry);
    }

    await writeTelemetry(telemetry, 'skipped', 'Unknown type');
    return { success: true, type, action: 'skipped', detail: 'Unknown type', confidence };

  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[orders-autopilot] processEmail error for ${id}:`, message);
    await writeTelemetry(telemetry, 'error', message.slice(0, 500));
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
  telemetry?: Partial<ClassificationLog>,
  tracer?: ParseTraceBuilder,
): Promise<ProcessEmailResult> {
  const { id, sender, date } = email;
  const tel = telemetry ?? { user_id: '', email_id: id };
  // Defensive: if a caller (test harness, future code path) reached
  // handlePurchaseConfirmation without going through processEmail, give
  // them a fresh tracer rather than scattering null-checks downstream.
  const trace = tracer ?? new ParseTraceBuilder(id);

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

  // Tier 4 change: always call the LLM on every purchase confirmation,
  // primarily to extract per-line ITEMS so the iOS card can render an
  // expanded detail view ("1× Hardgraft Tasche bag · 1× leather strap").
  // The LLM also opportunistically recovers merchant / order_number /
  // total when the regex extractors missed them. Merchant resolution
  // from the `learnedSender` / `known` paths is still locked below — we
  // don't second-guess explicit ground-truth on that axis.
  //
  // Skip the call only when the upstream caller already ran it (e.g.
  // the "other" → LLM-disagreed → promote-to-purchase path), in which
  // case we already have a fields object plus items list to use.
  let llm: LLMExtractedFields | null = preExtractedLLM ?? null;
  if (!preExtractedLLM) {
    tel.llm_called = true;
    llm = await extractWithLLM(email.subject, senderEmail, email.body);
    if (llm) {
      tel.llm_provider = llm.source;
      tel.llm_is_purchase = llm.is_purchase_confirmation;
      tel.llm_confidence = llm.confidence;
      tel.llm_merchant_name = llm.merchant_name ?? null;
      tel.llm_order_number = llm.order_number ?? null;
      trace.recordLLM({
        invoked: true,
        is_purchase: llm.is_purchase_confirmation,
        confidence: llm.confidence,
        provider: llm.source ?? null,
      });
    } else {
      tel.llm_provider = 'failed';
      trace.recordLLM({ invoked: true, is_purchase: null, confidence: null, provider: 'failed' });
    }
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
    normalizedMerchant: normalizeMerchant(mergedMerchantName),
    orderNumber: mergedOrderNumber,
    totalAmount: mergedTotal,
    currency: mergedCurrency,
  };

  if (!fields.merchantName || fields.merchantName === 'Unknown') {
    await writeTelemetry(tel, 'error', 'Could not identify merchant from email');
    return {
      success: false,
      type: 'purchase_confirmation',
      action: 'error',
      detail: 'Could not identify merchant from email',
      confidence: baseConfidence,
    };
  }

  // Record merchant resolution into the trace. Candidates list captures
  // alternates the resolver considered before locking in `selected` —
  // useful when the rule engine later asks "could we have picked a
  // different merchant?" Currently only LLM provides an alt; extend
  // when known-merchants / displayName paths surface their candidates.
  const merchantCandidates = [fields.merchantName];
  if (llm?.merchant_name && llm.merchant_name !== fields.merchantName) {
    merchantCandidates.push(llm.merchant_name);
  }
  trace.recordMerchant(fields.merchantName, fields.merchantSource ?? null, merchantCandidates);

  // Phase-1 Apple-bug fix: detect digital vs physical AFTER we've
  // confirmed it's a purchase. Digital purchases write with
  // status='digital' and skip shipment creation. The trace records
  // the decision + signals so the rule engine can later promote
  // sender-specific rules (e.g. "do@apple.com → always digital").
  const pd = detectPhysicalVsDigital(email.subject, email.body);
  trace.recordPhysicalDigital(pd);
  const orderStatus: 'ordered' | 'digital' = pd.decision === 'digital' ? 'digital' : 'ordered';

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
    status: orderStatus,
    parse_trace: trace.build(),
  });

  // Push to iOS via dashboard_records with category=commerce
  await pushCommerceRecord(orderId, 'order', fields, baseConfidence);

  // Persist per-line items extracted by the LLM. No-op when items[] is
  // empty (some orders have no extractable line items, e.g. a
  // subscription renewal email with just a total). When the LLM
  // returned items, replaceOrderItems wipes the previous list for
  // this order and writes the new one — items don't have stable
  // identity across re-extractions, so we keep one canonical list.
  if (llm && Array.isArray(llm.items) && llm.items.length > 0) {
    try {
      await replaceOrderItems(orderId, llm.items.map(it => ({
        name: it.name,
        quantity: it.quantity,
        unit_price: it.unit_price,
        currency: it.currency ?? fields.currency,
      })));
    } catch (err) {
      // Items are nice-to-have; never block order creation on them.
      console.warn(`[orders-autopilot] persisting items failed: ${err instanceof Error ? err.message : err}`);
    }
  }

  tel.merchant_source = fields.merchantSource;
  tel.resolved_merchant = fields.merchantName;
  tel.resolved_order_number = fields.orderNumber;
  tel.resolved_total_amount = fields.totalAmount;
  tel.resolved_currency = fields.currency;
  tel.related_order_id = orderId;
  await writeTelemetry(tel, isNew ? 'created_order' : 'updated_order',
    `${isNew ? 'Created' : 'Updated'} order: ${fields.merchantName}${fields.orderNumber ? ` #${fields.orderNumber}` : ''}`);

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
  telemetry?: Partial<ClassificationLog>,
): Promise<ProcessEmailResult> {
  const { id, sender } = email;
  const tel = telemetry ?? { user_id: '', email_id: id };

  const fields = extractShipmentFields(email.subject, email.body, sender, id);

  if (!fields.trackingNumber) {
    // No tracking number found — create a review item instead
    const reviewSenderEmail = (email.senderEmail
      || (sender.match(/<([^>]+)>/)?.[1])
      || sender).trim().toLowerCase();
    const reviewSenderName = (email.senderName
      || (sender.match(/^([^<]+)</)?.[1])
      || '').trim();
    const reviewId = await createReviewItem({
      user_id: await getUserIdFromEmail(sender),
      type: 'orphan_shipment',
      related_order_id: null,
      related_shipment_id: null,
      reason: `Shipping notification email from ${sender} but no tracking number could be extracted`,
      suggested_action: 'Review the email and manually add tracking number if valid',
      confidence_score: baseConfidence * 0.5,
      source_email_id: id,
      source_subject: email.subject?.slice(0, 500) ?? null,
      source_sender_email: reviewSenderEmail,
      source_sender_name: reviewSenderName || null,
    });

    tel.related_review_item_id = reviewId;
    await writeTelemetry(tel, 'created_review_item', 'No tracking number found');
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
    await writeTelemetry(tel, 'skipped', `Tracking ${fields.trackingNumber} already linked`);
    return {
      success: true,
      type: 'shipping_notification',
      action: 'skipped',
      detail: `Tracking ${fields.trackingNumber} already linked to an order`,
      confidence: baseConfidence,
    };
  }

  // Resolve merchant for the shipment-to-order link.
  //
  // For non-carrier senders, the sender's display-name / domain stem is
  // a reliable merchant signal — a Hardgraft shipping email comes from
  // hardgraft.com and we want merchant = "Hardgraft".
  //
  // For carrier senders (Correos, DHL, UPS, …), the sender IS the
  // carrier — useless for matching. We try TWO things in order:
  //   1. CROSS-REFERENCE: search the inbox for the tracking number;
  //      the originating order-confirmation email almost always
  //      mentions it. THAT email's sender is the actual merchant.
  //      This is the most reliable signal — a Correos email may
  //      mention "Amazon" in body boilerplate even when the order
  //      is from Nomos.
  //   2. BODY RECOVERY: scan the carrier email's body against the
  //      KNOWN_MERCHANTS list. Used when cross-reference returns
  //      nothing (token throttled, search miss, etc.).
  let merchantName: string;
  const senderEmailLower = (email.senderEmail || sender).toLowerCase();
  if (senderIsCarrier(senderEmailLower)) {
    const xref = await findSourceMerchantFromTracking(fields.trackingNumber, id);
    if (xref) {
      merchantName = xref.merchant;
      // Log to STDERR (not STDOUT) so the cli's JSON response on
      // STDOUT stays parseable. console.info goes to stdout in Node.
      console.error(`[orders-autopilot] cross-reference found merchant '${xref.merchant}' for tracking ${fields.trackingNumber} via email ${xref.sourceEmailId}`);
    } else {
      // Cross-reference miss — fall back to body recovery.
      const bodyMerchant = inferMerchantNameFromBody(email.body);
      merchantName = bodyMerchant ?? extractOrderFields(email.subject, email.body, sender, id).merchantName;
    }
  } else {
    merchantName = extractOrderFields(email.subject, email.body, sender, id).merchantName;
  }
  const normalizedMerchant = merchantName ? normalizeMerchant(merchantName) : '';

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
    const reviewSenderEmail = (email.senderEmail
      || (sender.match(/<([^>]+)>/)?.[1])
      || sender).trim().toLowerCase();
    const reviewSenderName = (email.senderName
      || (sender.match(/^([^<]+)</)?.[1])
      || '').trim();
    const reviewId = await createReviewItem({
      user_id: userId,
      type: 'shipment_no_order',
      related_order_id: null,
      related_shipment_id: null,
      reason: `Shipment with tracking ${fields.trackingNumber} (${fields.carrier || 'unknown carrier'}) could not be matched to any order`,
      suggested_action: 'Link this shipment to the correct order or mark as standalone',
      confidence_score: baseConfidence * 0.6,
      source_email_id: id,
      source_subject: email.subject?.slice(0, 500) ?? null,
      source_sender_email: reviewSenderEmail,
      source_sender_name: reviewSenderName || null,
      suggested_merchant: merchantName,
    });

    tel.related_review_item_id = reviewId;
    await writeTelemetry(tel, 'created_review_item', `Tracking ${fields.trackingNumber} could not be matched to an order`);
    return {
      success: true,
      type: 'shipping_notification',
      action: 'created_review_item',
      detail: `Tracking ${fields.trackingNumber} could not be matched to an order — created review item`,
      confidence: baseConfidence,
    };
  }

  // Phase 1 ETA: pick the highest-ranked ETA candidate from the
  // email body (if any), then run it through resolveETAUpdate
  // against the existing shipment row's ETA. Skip the write if the
  // resolver says "no update" (e.g. existing 17track ETA outranks
  // this carrier-email ETA).
  let etaUpdate: { eta_at: string; eta_source: 'carrier_email'; eta_recorded_at: string } | null = null;
  const etaWinner = pickETA(fields.etaCandidates, new Date());
  if (etaWinner) {
    const { data: existingShipment } = await supabase
      .from('shipments')
      .select('eta_at, eta_source, eta_recorded_at')
      .eq('order_id', orderId)
      .eq('tracking_number', fields.trackingNumber)
      .maybeSingle();
    const now = new Date();
    const resolved = resolveETAUpdate(
      {
        eta_at: existingShipment?.eta_at ? new Date(existingShipment.eta_at) : null,
        eta_source: (existingShipment?.eta_source as string | null) ?? null,
        eta_recorded_at: existingShipment?.eta_recorded_at ? new Date(existingShipment.eta_recorded_at) : null,
      },
      {
        eta_at: etaWinner.date,
        eta_source: 'carrier_email',
        eta_recorded_at: now,
      },
    );
    if (resolved) {
      etaUpdate = {
        eta_at: resolved.eta_at.toISOString(),
        eta_source: resolved.eta_source as 'carrier_email',
        eta_recorded_at: resolved.eta_recorded_at.toISOString(),
      };
    }
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
    ...(etaUpdate ?? {}),
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

  tel.related_order_id = orderId;
  await writeTelemetry(tel, 'linked_shipment', `Linked tracking ${fields.trackingNumber} to order`);
  return {
    success: true,
    type: 'shipping_notification',
    action: 'linked_shipment',
    detail: `Linked tracking ${fields.trackingNumber} to order`,
    confidence: baseConfidence,
  };
}

// ─── Tracking → originating-merchant cross-reference ──────────────────────

/**
 * Given a tracking number from a carrier email, search the inbox for
 * OTHER emails (not the carrier email itself, not other carrier
 * emails) that mention the same tracking number. The first
 * non-carrier hit is almost always the merchant's order-confirmation
 * email — the sender field of THAT email is the most reliable signal
 * for which merchant the shipment actually belongs to.
 *
 * Returns null on:
 *   - JMAP token unavailable / search call failed (best-effort)
 *   - No non-carrier emails found mentioning the tracking number
 *   - Candidates exist but none yield a usable merchant via the
 *     known-list / cleanDisplayName paths
 *
 * Caught-in-the-wild motivating example: a Correos shipping email
 * with body text mentioning "Amazon" was creating an Amazon shipment,
 * but searching the inbox for the tracking number found a Nomos
 * order-confirmation email — the actual merchant was Nomos. Without
 * cross-reference we'd have silently mislabeled the merchant forever.
 */
async function findSourceMerchantFromTracking(
  trackingNumber: string,
  excludeEmailId: string,
): Promise<{ merchant: string; sourceEmailId: string; source: 'known_domain' | 'sender_name' } | null> {
  if (!trackingNumber || trackingNumber.length < 6) return null;
  const candidates = await searchEmailsByText(trackingNumber, 8);

  for (const c of candidates) {
    if (c.id === excludeEmailId) continue;
    if (senderIsCarrier(c.fromEmail)) continue;

    // 1. Try the alphanum-normalized known-list match against the
    //    sender's email + display name. Catches "Hardgraft", "Body&Fit",
    //    "Matador" etc. — the merchants we already curate.
    const senderJoined = `${c.fromEmail} ${c.fromName}`;
    const known = inferMerchantNameFromBody(senderJoined);
    if (known) {
      return { merchant: known, sourceEmailId: c.id, source: 'known_domain' };
    }

    // 2. Fall back to the cleaned sender display name. Strips
    //    "Customer Service" / "Support" / etc. suffixes. Returns a
    //    plausible merchant name even when the merchant isn't on the
    //    hardcoded list (e.g. Nomos, Aesop in the wild).
    const cleaned = cleanDisplayName(c.fromName);
    if (cleaned) {
      return { merchant: cleaned, sourceEmailId: c.id, source: 'sender_name' };
    }
  }

  return null;
}

// ─── Telemetry helper ──────────────────────────────────────────────────────

/**
 * Finalize and persist a classification telemetry row. Best-effort:
 * never throws, never blocks the pipeline. A missing user_id silently
 * drops the write (telemetry without ownership is meaningless and
 * would violate RLS anyway).
 */
async function writeTelemetry(
  tel: Partial<ClassificationLog>,
  finalAction: ClassificationLog['final_action'],
  detail?: string,
): Promise<void> {
  if (!tel.user_id || !tel.email_id) return;
  await recordClassification({
    ...(tel as ClassificationLog),
    final_action: finalAction,
    detail: detail ?? tel.detail ?? null,
  });
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
      // Phase 1 ETA: resolve 17track's estimated_delivery_date against
      // the shipment's current eta_* triplet. resolve17trackETA returns
      // null when no overwrite is warranted (e.g. 17track silent, or
      // existing source has higher priority).
      const etaUpdate = await resolve17trackETA(shipment.id!, trackerData.eta_at);

      await updateShipmentFromTracker(shipment.id!, {
        status: trackerData.status,
        checkpoint: trackerData.latest_checkpoint || undefined,
        shipped_at: trackerData.shipped_at || undefined,
        delivered_at: trackerData.delivered_at || undefined,
        ...(etaUpdate ?? {}),
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
  // ─── Phase 3: snapshot pre-update state for event-insight detection ───
  // We need the previous status + ETA to compare against the new values
  // and the merchant name to feed into the BioChecha event script.
  const { data: priorShipment } = await supabase
    .from('shipments')
    .select('status, eta_at, order_id')
    .eq('id', shipmentId)
    .maybeSingle();

  let merchantName: string | null = null;
  if (priorShipment?.order_id) {
    const { data: priorOrder } = await supabase
      .from('orders')
      .select('merchant_name')
      .eq('id', priorShipment.order_id)
      .maybeSingle();
    merchantName = priorOrder?.merchant_name ?? null;
  }

  const result = await pollSingleShipment(apiKey, trackingNumber, carrier || undefined);
  const etaUpdate = await resolve17trackETA(shipmentId, result.eta_at);

  await updateShipmentFromTracker(shipmentId, {
    status: result.status,
    checkpoint: result.latest_checkpoint || undefined,
    shipped_at: result.shipped_at || undefined,
    delivered_at: result.delivered_at || undefined,
    ...(etaUpdate ?? {}),
  });

  // ─── Phase 3: event-insight hook ───────────────────────────────
  //
  // Detect two transitions worth a fresh BioChecha event insight:
  //   1. status flipped to `out_for_delivery` (was anything else)
  //   2. ETA went from no-eta-or-future to today
  //
  // The Python script handles don't-churn internally (skips if a
  // recent insight already covers this tracking number).
  try {
    const previouslyOFD = priorShipment?.status === 'out_for_delivery';
    const nowOFD = result.status === 'out_for_delivery';
    if (nowOFD && !previouslyOFD) {
      fireEventInsight([
        'out_for_delivery',
        merchantName ?? 'Unknown',
        carrier ?? 'unknown',
        trackingNumber,
        priorShipment?.status ?? 'unknown',
        'out_for_delivery',
      ]);
    }

    if (etaUpdate?.eta_at) {
      const newEtaDate = new Date(etaUpdate.eta_at).toDateString();
      const oldEtaDate = priorShipment?.eta_at
        ? new Date(priorShipment.eta_at).toDateString()
        : '';
      const todayDate = new Date().toDateString();
      if (newEtaDate === todayDate && oldEtaDate !== todayDate) {
        fireEventInsight([
          'eta_today',
          merchantName ?? 'Unknown',
          carrier ?? 'unknown',
          trackingNumber,
          etaUpdate.eta_at,
        ]);
      }
    }
  } catch (err) {
    // Never let event-insight failure break tracking updates.
    console.warn('[event-insight] hook error:', (err as Error).message);
  }
}

/**
 * Fire-and-forget shellout to biochecha_event_insight.py. Called when
 * 17track polling detects a status flip or ETA change. The Python
 * script handles its own idempotency via the don't-churn guard.
 *
 * Path resolution: $HOME/.openclaw/workspace/scripts/health-integrations/
 * biochecha_event_insight.py is the canonical install location (see
 * SETUP-FOR-AGENTS.md).
 */
function fireEventInsight(args: string[]): void {
  const home = process.env.HOME || '';
  const scriptPath = `${home}/.openclaw/workspace/scripts/health-integrations/biochecha_event_insight.py`;
  const proc = spawn('python3', [scriptPath, ...args], {
    detached: true,
    stdio: 'ignore',
  });
  proc.unref();  // allow parent to exit independently
  proc.on('error', (err) => {
    // Log and swallow — never let this block the poll loop.
    console.error('[event-insight] spawn failed:', err.message);
  });
}

/**
 * Phase 1 ETA: when 17track returns an estimated_delivery_date,
 * fetch the shipment's current eta_* triplet and run the resolver
 * to decide whether to overwrite. Returns the fields to merge into
 * the update payload, or null when no update should happen
 * (17track returned null, or current ETA outranks the new one).
 */
async function resolve17trackETA(
  shipmentId: string,
  trackerETA: string | null,
): Promise<{ eta_at: string; eta_source: '17track'; eta_recorded_at: string } | null> {
  if (!trackerETA) return null;     // 17track silent — never overwrite
  const parsed = new Date(trackerETA);
  if (isNaN(parsed.getTime())) return null;

  const { data: existing } = await supabase
    .from('shipments')
    .select('eta_at, eta_source, eta_recorded_at')
    .eq('id', shipmentId)
    .maybeSingle();

  const now = new Date();
  const resolved = resolveETAUpdate(
    {
      eta_at: existing?.eta_at ? new Date(existing.eta_at) : null,
      eta_source: (existing?.eta_source as string | null) ?? null,
      eta_recorded_at: existing?.eta_recorded_at ? new Date(existing.eta_recorded_at) : null,
    },
    {
      eta_at: parsed,
      eta_source: '17track',
      eta_recorded_at: now,
    },
  );
  if (!resolved) return null;
  return {
    eta_at: resolved.eta_at.toISOString(),
    eta_source: '17track',
    eta_recorded_at: resolved.eta_recorded_at.toISOString(),
  };
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
