/**
 * quoted-prior-order.ts
 *
 * Demo Foams-bug fix (2026-04-27): a customer-satisfaction reply ("How
 * are you enjoying your foam mattress?") was being parsed as a NEW
 * order because the body quoted the original purchase confirmation
 * verbatim, including "Order #12345". Tier 1 + Tier 2 both saw the
 * order number and merchant signals and confidently created a
 * duplicate.
 *
 * This module runs BEFORE classification. If subject is a Re:/Fwd:
 * AND body mentions an order number that the user ALREADY owns from
 * the same merchant, we short-circuit to 'other' and skip the rest of
 * the pipeline.
 *
 * Multilingual coverage matches the existing scanner's locale set.
 */

import type { SupabaseClient } from '@supabase/supabase-js';

// Reply prefixes — covers EN/DE/PT/ES/FR/IT/NL.
const REPLY_PREFIX_RE = /^\s*(re|fwd|fw|aw|tr|res|enc|rv|ant)\s*:/i;

// Multilingual "order number" capture. Matches:
//   "Order #12345" / "order: 12345" / "order 12345"
//   "Pedido #12345" (PT/ES)
//   "Bestelnummer 12345" / "Bestelling 12345" (NL)
//   "Commande N° 12345" (FR)
//   "Bestellung Nr 12345" (DE)
//   "Ordine #12345" (IT)
const ORDER_NUMBER_RES: ReadonlyArray<RegExp> = [
  /\b(?:order|pedido|bestelling|bestelnummer|commande|bestellung|ordine)[\s#:№nr.°]*([A-Z0-9-]{3,})/gi,
  /\bn[°º]\s*([A-Z0-9-]{4,})/gi,
];

export interface QuotedPriorOrderResult {
  matched: boolean;
  matched_order_number?: string;
  match_source?: 'subject_re_plus_body_order_number';
}

/**
 * Detect whether this email is a reply that quotes a prior order.
 *
 * Returns `matched: true` only when ALL of:
 *   - Subject begins with a reply prefix (Re:, Fwd:, Aw:, etc.)
 *   - Body contains a parseable "Order #X" or equivalent
 *   - The captured order number X already exists in `orders` for this
 *     user + normalized_merchant
 *
 * @param supabase — caller-provided client (lets the lookup run with
 *                   service-role privileges in the autopilot context).
 */
export async function detectQuotedPriorOrder(args: {
  subject: string;
  body: string;
  userId: string;
  normalizedMerchant: string | null;
  supabase: SupabaseClient;
}): Promise<QuotedPriorOrderResult> {
  const { subject, body, userId, normalizedMerchant, supabase } = args;

  if (!REPLY_PREFIX_RE.test(subject || '')) {
    return { matched: false };
  }
  if (!normalizedMerchant) {
    // Without a merchant we can't safely look up; skip (will not short-circuit).
    return { matched: false };
  }

  // Collect candidate order numbers from the body. Multiple candidates
  // are common in quoted replies (e.g. body has both an order-number
  // line and a returns-portal URL with the same number); we look up
  // each until we find a hit.
  const candidates = new Set<string>();
  for (const re of ORDER_NUMBER_RES) {
    re.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(body)) !== null && candidates.size < 6) {
      const captured = (m[1] || '').replace(/^#/, '').trim();
      // Filter trivial false-positives: very long alphanumerics (likely
      // tracking numbers) or pure 1-2 digit fragments.
      if (captured.length >= 3 && captured.length <= 24) {
        candidates.add(captured);
      }
    }
  }

  if (candidates.size === 0) return { matched: false };

  // Look up each candidate against (user, normalized_merchant).
  const { data, error } = await supabase
    .from('orders')
    .select('order_number')
    .eq('user_id', userId)
    .eq('normalized_merchant', normalizedMerchant)
    .in('order_number', Array.from(candidates))
    .limit(1);

  if (error) {
    // Swallow lookup errors — short-circuit is opportunistic, not required.
    // Without it we fall through to the classifier as if this fix didn't exist.
    return { matched: false };
  }

  const hit = data && data[0];
  if (!hit || !hit.order_number) return { matched: false };

  return {
    matched: true,
    matched_order_number: hit.order_number,
    match_source: 'subject_re_plus_body_order_number',
  };
}
