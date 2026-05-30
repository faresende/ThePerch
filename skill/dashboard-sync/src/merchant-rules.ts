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

// The live DB CHECK is ('skip_purchase','always_physical','always_digital').
// The legacy 'require_review' action was never shipped server-side and has
// been dropped; the classification cascade consumes always_physical /
// always_digital directly (skip_purchase still drops the email).
export type MerchantRuleAction = 'skip_purchase' | 'always_physical' | 'always_digital';

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

// ─── One-answer learning (classification rework) ─────────────────────
// The review queue asks the user a single question about an ambiguous
// commerce email; their answer becomes a durable merchant_rule so we
// never re-ask. This is the PURE mapping helper — it just turns the
// (subject, answer) pair into a rule spec. The DB-side write
// (applyReviewAnswer) + the retroactive sweep over already-classified
// emails are wired in a later phase.

/** The three answers the review card offers. */
export type ReviewAnswer = 'yes_track' | 'no_package' | 'bought_but_digital';

/** The minimal identity of the merchant the user is answering about. */
export interface ReviewSubject {
  senderEmail: string | null;
  normalizedMerchant: string;
}

/** A merchant_rule the learning loop wants written. */
export interface MerchantRuleSpec {
  match_kind: 'sender_email' | 'sender_domain' | 'normalized_merchant';
  match_value: string;
  action: 'always_physical' | 'always_digital' | 'skip_purchase';
}

/**
 * Map a single review answer to a merchant_rule spec, anchored on the
 * MOST SPECIFIC signal available: prefer the exact sender email (so the
 * rule is tight), otherwise fall back to the normalized merchant name.
 *
 *   yes_track          → always_physical (surface this sender's packages)
 *   bought_but_digital → always_digital  (real purchase, nothing ships)
 *   no_package         → skip_purchase   (not a trackable order at all)
 */
export function ruleFromReviewAnswer(subj: ReviewSubject, answer: ReviewAnswer): MerchantRuleSpec {
  const action: MerchantRuleSpec['action'] =
    answer === 'yes_track' ? 'always_physical' : answer === 'bought_but_digital' ? 'always_digital' : 'skip_purchase';
  if (subj.senderEmail) {
    return { match_kind: 'sender_email', match_value: subj.senderEmail.toLowerCase(), action };
  }
  return { match_kind: 'normalized_merchant', match_value: subj.normalizedMerchant, action };
}

/** The exact param object the `apply_review_answer` RPC expects. */
export interface ReviewAnswerRpcParams {
  p_user_id: string;
  p_match_kind: MerchantRuleSpec['match_kind'];
  p_match_value: string;
  p_action: MerchantRuleSpec['action'];
  p_review_item_id: string | null;
}

/**
 * PURE core of `applyReviewAnswer`: turn a (user, subject, answer) tuple plus
 * the triggering review-item id into the exact named params the
 * `apply_review_answer` SECURITY DEFINER RPC expects. Delegates the
 * (subject, answer) → rule-spec decision to `ruleFromReviewAnswer` so the
 * answer→action mapping lives in exactly one place. `reviewItemId` (incl.
 * null) passes straight through.
 */
export function reviewAnswerRpcParams(
  userId: string,
  subj: ReviewSubject,
  answer: ReviewAnswer,
  reviewItemId: string | null,
): ReviewAnswerRpcParams {
  const rule = ruleFromReviewAnswer(subj, answer);
  return {
    p_user_id: userId,
    p_match_kind: rule.match_kind,
    p_match_value: rule.match_value,
    p_action: rule.action,
    p_review_item_id: reviewItemId,
  };
}

/**
 * Apply a single review answer through the `apply_review_answer` RPC: it
 * upserts the durable merchant_rule, retroactively sweeps already-captured
 * sibling orders to match the verdict, and resolves the triggering +
 * sibling review items — all server-side and atomic. Returns the number of
 * orders swept (0 when the RPC returns a non-numeric payload).
 *
 * Unlike the best-effort `lookupMerchantRule`, errors here are THROWN: this
 * runs in response to a user tap and iOS surfaces failures to the user.
 */
export async function applyReviewAnswer(
  userId: string,
  subj: ReviewSubject,
  answer: ReviewAnswer,
  reviewItemId: string | null = null,
): Promise<number> {
  const { data, error } = await supabase.rpc(
    'apply_review_answer',
    reviewAnswerRpcParams(userId, subj, answer, reviewItemId),
  );
  if (error) {
    throw new Error(`apply_review_answer RPC failed: ${error.message}`);
  }
  return typeof data === 'number' ? data : 0;
}
