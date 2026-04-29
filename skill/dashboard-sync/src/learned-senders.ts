/**
 * learned-senders.ts
 *
 * Read/write helpers for the `public.learned_senders` table — the user-curated
 * (sender → merchant) mapping populated when the user resolves rows in the
 * iOS Settings → Order Review queue.
 *
 * The orders-autopilot pipeline calls `lookupLearnedSender` BEFORE its
 * built-in keyword classifier; if a row matches, that merchant_name wins
 * over both the hardcoded `known` list and any LLM second-pass.
 *
 * The review-queue UI calls `recordLearnedSender` after the user confirms
 * "yes, this sender is X" so the same email-pattern is never misclassified
 * twice.
 *
 * Match priority (matches the SQL semantics):
 *   1. Exact (user_id, sender_email) — the user explicitly taught us this.
 *   2. (user_id, sender_domain)      — fallback when the merchant rotates
 *                                      noreply@/orders@/hello@ but keeps
 *                                      the same domain stem.
 */

import { supabase } from './supabase';
import { normalizeMerchant } from './email-classifier';

export interface LearnedSender {
  id: string;
  user_id: string;
  sender_email: string;
  sender_domain: string | null;
  merchant_name: string;
  normalized_merchant: string;
  learned_from_email_id: string | null;
  learned_from_review_item_id: string | null;
  created_at: string;
  updated_at: string;
}

export interface LearnedSenderMatch {
  merchant_name: string;
  normalized_merchant: string;
  matched_on: 'sender_email' | 'sender_domain';
}

/**
 * Derive the lowercase domain stem from a sender email.
 *   "Orders@HardGraft.com"  → "hardgraft"
 *   "store+abc@t.shopifyemail.com" → "shopifyemail"
 *   ""                       → null
 */
export function senderDomainStem(senderEmail: string): string | null {
  if (!senderEmail) return null;
  const lower = senderEmail.toLowerCase();
  const at = lower.indexOf('@');
  if (at < 0) return null;
  const host = lower.slice(at + 1).replace(/^www\./, '');
  // Drop subdomains by taking the second-to-last label when there is one
  // (e.g. "t.shopifyemail.com" → "shopifyemail"). Falls back to the first
  // label for short hosts.
  const parts = host.split('.').filter(Boolean);
  if (parts.length >= 2) return parts[parts.length - 2];
  return parts[0] ?? null;
}

/**
 * Lowercase, alphanumeric-only, accent-folded version of a merchant
 * name. Re-exports `normalizeMerchant` from email-classifier so a
 * learned mapping lines up EXACTLY with the
 * `orders.normalized_merchant` column — including accent-folding
 * ("Glashütte" → "glashutte" not "glashtte"). Drift between callers
 * re-creates the dupe-orders / unmatched-shipment bug we caught with
 * the FedEx 513453603758 cross-ref.
 */
export const normalizeMerchantName = normalizeMerchant;

/**
 * Look up a learned (sender → merchant) mapping for this user. Returns
 * null when no match — caller should fall back to keyword/LLM logic.
 *
 * Match order is enforced in JS so we can label which axis hit, but the
 * SQL query is collapsed into a single round-trip via PostgREST's `or`
 * filter: we ask for any row matching the exact email OR the sender
 * domain, then pick the best match in JS. Saves one network hop on every
 * email through the autopilot.
 *
 *   1. exact sender_email
 *   2. sender_domain fallback
 */
export async function lookupLearnedSender(
  userId: string,
  senderEmail: string,
): Promise<LearnedSenderMatch | null> {
  const email = (senderEmail || '').trim().toLowerCase();
  if (!email) return null;

  const domain = senderDomainStem(email);

  // Single round-trip: fetch any row that matches by exact email OR
  // (when we can derive one) the sender domain. We then pick the best
  // match in JS so the matched_on label stays accurate.
  const orFilter = domain
    ? `sender_email.eq.${email},sender_domain.eq.${domain}`
    : `sender_email.eq.${email}`;

  const { data: rows, error } = await supabase
    .from('learned_senders')
    .select('merchant_name, normalized_merchant, sender_email, sender_domain, updated_at')
    .eq('user_id', userId)
    .or(orFilter)
    .order('updated_at', { ascending: false })
    .limit(8); // small cap so a noisy domain doesn't pull a huge page

  if (error) {
    console.warn(`[learned-senders] lookup failed: ${error.message}`);
    // Don't propagate — a stale lookup shouldn't break the pipeline.
    return null;
  }
  if (!rows || rows.length === 0) return null;

  // Prefer exact email match if present; otherwise the most recent
  // domain match (rows are already sorted updated_at DESC).
  const exact = rows.find(r => r.sender_email === email);
  if (exact) {
    return {
      merchant_name: exact.merchant_name,
      normalized_merchant: exact.normalized_merchant,
      matched_on: 'sender_email',
    };
  }

  if (!domain) return null;
  const domainHit = rows.find(r => r.sender_domain === domain);
  if (domainHit) {
    return {
      merchant_name: domainHit.merchant_name,
      normalized_merchant: domainHit.normalized_merchant,
      matched_on: 'sender_domain',
    };
  }

  return null;
}

/**
 * Upsert a learned mapping for this user. Called when the user resolves a
 * review-queue row by setting / confirming the merchant.
 *
 * Existing (user_id, sender_email) rows are updated in place; new rows are
 * inserted. Returns the row id.
 */
export async function recordLearnedSender(
  args: {
    userId: string;
    senderEmail: string;
    merchantName: string;
    learnedFromEmailId?: string | null;
    learnedFromReviewItemId?: string | null;
  },
): Promise<string> {
  const email = (args.senderEmail || '').trim().toLowerCase();
  if (!email) throw new Error('recordLearnedSender: senderEmail is required');
  const merchant = (args.merchantName || '').trim();
  if (!merchant) throw new Error('recordLearnedSender: merchantName is required');

  const domain = senderDomainStem(email);
  const normalized = normalizeMerchantName(merchant);
  if (!normalized) {
    throw new Error(`recordLearnedSender: merchant_name "${merchant}" normalizes to empty`);
  }

  const now = new Date().toISOString();
  const payload = {
    user_id: args.userId,
    sender_email: email,
    sender_domain: domain,
    merchant_name: merchant,
    normalized_merchant: normalized,
    learned_from_email_id: args.learnedFromEmailId ?? null,
    learned_from_review_item_id: args.learnedFromReviewItemId ?? null,
    created_at: now,
    updated_at: now,
  };

  // Native PostgREST upsert. The unique index `learned_senders_user_email_unique`
  // on (user_id, sender_email) is the conflict target; on conflict the
  // matching row is updated, otherwise a new row is inserted. One round-trip
  // instead of the previous find-then-update-or-insert pair.
  const { data, error } = await supabase
    .from('learned_senders')
    .upsert([payload], { onConflict: 'user_id,sender_email', ignoreDuplicates: false })
    .select('id')
    .single();
  if (error) throw new Error(`learned_senders upsert failed: ${error.message}`);
  return data.id;
}

/**
 * List all learned-sender rows for a user. Used by the iOS Settings UI
 * (Tier 3) to show the review queue's "what I've taught the system" list.
 */
export async function listLearnedSenders(userId: string): Promise<LearnedSender[]> {
  const { data, error } = await supabase
    .from('learned_senders')
    .select('*')
    .eq('user_id', userId)
    .order('updated_at', { ascending: false });
  if (error) throw new Error(`learned_senders list failed: ${error.message}`);
  return (data ?? []) as LearnedSender[];
}

/**
 * Delete a learned mapping (user revoked it from the iOS Settings UI).
 */
export async function deleteLearnedSender(userId: string, id: string): Promise<void> {
  const { error } = await supabase
    .from('learned_senders')
    .delete()
    .eq('user_id', userId)
    .eq('id', id);
  if (error) throw new Error(`learned_senders delete failed: ${error.message}`);
}
