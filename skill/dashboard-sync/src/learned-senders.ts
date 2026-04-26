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
 * Match order is enforced in JS (not SQL) so we can label which axis hit:
 *   1. exact sender_email
 *   2. sender_domain fallback
 */
export async function lookupLearnedSender(
  userId: string,
  senderEmail: string,
): Promise<LearnedSenderMatch | null> {
  const email = (senderEmail || '').trim().toLowerCase();
  if (!email) return null;

  // 1. exact email match.
  const { data: exact, error: exactErr } = await supabase
    .from('learned_senders')
    .select('merchant_name, normalized_merchant')
    .eq('user_id', userId)
    .eq('sender_email', email)
    .maybeSingle();

  if (exactErr) {
    console.warn(`[learned-senders] exact lookup failed: ${exactErr.message}`);
    // Don't propagate — a stale lookup shouldn't break the pipeline.
    return null;
  }
  if (exact) {
    return {
      merchant_name: exact.merchant_name,
      normalized_merchant: exact.normalized_merchant,
      matched_on: 'sender_email',
    };
  }

  // 2. domain fallback.
  const domain = senderDomainStem(email);
  if (!domain) return null;

  const { data: domainHit, error: domainErr } = await supabase
    .from('learned_senders')
    .select('merchant_name, normalized_merchant')
    .eq('user_id', userId)
    .eq('sender_domain', domain)
    .order('updated_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (domainErr) {
    console.warn(`[learned-senders] domain lookup failed: ${domainErr.message}`);
    return null;
  }
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

  const payload = {
    user_id: args.userId,
    sender_email: email,
    sender_domain: domain,
    merchant_name: merchant,
    normalized_merchant: normalized,
    learned_from_email_id: args.learnedFromEmailId ?? null,
    learned_from_review_item_id: args.learnedFromReviewItemId ?? null,
    updated_at: new Date().toISOString(),
  };

  // Try update first (matches the unique index on (user_id, sender_email)).
  const { data: existing, error: findErr } = await supabase
    .from('learned_senders')
    .select('id')
    .eq('user_id', args.userId)
    .eq('sender_email', email)
    .maybeSingle();

  if (findErr) {
    throw new Error(`learned_senders find failed: ${findErr.message}`);
  }

  if (existing) {
    const { data, error } = await supabase
      .from('learned_senders')
      .update(payload)
      .eq('id', existing.id)
      .select('id')
      .single();
    if (error) throw new Error(`learned_senders update failed: ${error.message}`);
    return data.id;
  }

  const { data, error } = await supabase
    .from('learned_senders')
    .insert([{ ...payload, created_at: new Date().toISOString() }])
    .select('id')
    .single();
  if (error) throw new Error(`learned_senders insert failed: ${error.message}`);
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
