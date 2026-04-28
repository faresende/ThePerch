/**
 * merchant-rules.ts
 *
 * Phase 2 of the corrections-and-rules feedback loop. Reads
 * `public.merchant_rules` to short-circuit the orders autopilot
 * BEFORE the classifier runs.
 *
 * Rule lifecycle:
 *   1. User swipes "Not an order" on a confirmed order →
 *      `record_order_correction` RPC inserts an order_corrections
 *      row AND calls `promote_merchant_rules` on the same user.
 *   2. promote_merchant_rules counts not_an_order corrections in
 *      the last 60 days, joined to email_classifications via
 *      source_email_ids. Domains with ≥3 corrections get an
 *      auto-promoted rule (action=skip_purchase).
 *   3. Subsequent emails from that domain hit `applyMerchantRule`
 *      below; processEmail returns early with action='skipped'.
 *
 * Both lookup and promotion run server-side via SECURITY DEFINER
 * RPCs. iOS Settings can read/write the table directly under RLS
 * for the user-curated rules path.
 */

import { supabase } from './supabase';

export type MerchantRuleAction = 'skip_purchase' | 'require_review';

export interface MerchantRuleMatch {
  rule_id: string;
  match_kind: 'sender_email' | 'sender_domain' | 'normalized_merchant';
  match_value: string;
  action: MerchantRuleAction;
}

/**
 * Look up the first enabled merchant rule that matches this email.
 *
 * Priority (server-side, see migration 20260428130000):
 *   1. exact sender_email
 *   2. sender_domain (split on @)
 *   3. normalized_merchant (only when caller has inferred one)
 *
 * Returns null when nothing matches OR the lookup fails. Caller
 * MUST treat null as "fall through to normal classification".
 *
 * Best-effort: a network failure here should never block an email
 * from being processed. Errors are logged and swallowed.
 */
export async function lookupMerchantRule(
  userId: string,
  senderEmail: string,
  normalizedMerchant: string | null = null,
): Promise<MerchantRuleMatch | null> {
  if (!senderEmail || !senderEmail.includes('@')) return null;

  try {
    const { data, error } = await supabase.rpc('apply_merchant_rule', {
      p_user_id: userId,
      p_sender_email: senderEmail,
      p_normalized_merchant: normalizedMerchant,
    });
    if (error) {
      console.warn('[merchant-rules] apply_merchant_rule RPC failed:', error.message);
      return null;
    }
    if (!Array.isArray(data) || data.length === 0) return null;
    const row = data[0];
    if (!row?.rule_id || !row?.action) return null;
    return {
      rule_id: row.rule_id,
      match_kind: row.match_kind,
      match_value: row.match_value,
      action: row.action,
    };
  } catch (err) {
    console.warn('[merchant-rules] lookup threw:', (err as Error).message);
    return null;
  }
}
