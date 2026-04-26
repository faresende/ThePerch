/**
 * classifications-store.ts
 *
 * Telemetry write path for the orders-autopilot pipeline. Every email
 * the pipeline sees produces exactly one row in `public.email_classifications`
 * — Tier 1 keyword scores, LLM verdict (when called), learned-senders match,
 * final action, what we resolved as the merchant / order number / total.
 *
 * This is fire-and-forget: a telemetry write failure must never break the
 * pipeline. Wrap every call in try/catch on the autopilot side.
 */

import { supabase } from './supabase';
import type { EmailType } from './email-classifier';
import type { MerchantSource } from './email-classifier';
import type { LLMExtractedFields } from './llm-extractor';

/** Final outcome the autopilot reached for the email. */
export type ClassificationFinalAction =
  | 'created_order'
  | 'updated_order'
  | 'linked_shipment'
  | 'created_review_item'
  | 'skipped'
  | 'error';

export interface ClassificationLog {
  user_id: string;
  email_id: string;
  subject?: string | null;
  sender_email?: string | null;
  sender_name?: string | null;

  tier1_purchase_score?: number | null;
  tier1_shipping_score?: number | null;
  tier1_type?: EmailType | null;
  tier1_confidence?: number | null;
  tier1_matched_keywords?: string[] | null;

  llm_called?: boolean;
  llm_provider?: LLMExtractedFields['source'] | null;
  llm_is_purchase?: boolean | null;
  llm_confidence?: number | null;
  llm_merchant_name?: string | null;
  llm_order_number?: string | null;

  learned_sender_matched?: boolean;
  learned_sender_match_axis?: 'sender_email' | 'sender_domain' | null;

  final_action: ClassificationFinalAction;
  merchant_source?: MerchantSource;
  resolved_merchant?: string | null;
  resolved_order_number?: string | null;
  resolved_total_amount?: number | null;
  resolved_currency?: string | null;

  related_order_id?: string | null;
  related_review_item_id?: string | null;

  detail?: string | null;
}

/**
 * Persist a classification record. Best-effort: errors are logged to
 * stderr but never thrown — telemetry should never break the pipeline.
 */
export async function recordClassification(log: ClassificationLog): Promise<void> {
  try {
    const payload = {
      user_id: log.user_id,
      email_id: log.email_id,
      subject: log.subject ?? null,
      sender_email: log.sender_email ?? null,
      sender_name: log.sender_name ?? null,
      tier1_purchase_score: log.tier1_purchase_score ?? null,
      tier1_shipping_score: log.tier1_shipping_score ?? null,
      tier1_type: log.tier1_type ?? null,
      tier1_confidence: log.tier1_confidence ?? null,
      tier1_matched_keywords: log.tier1_matched_keywords ?? null,
      llm_called: !!log.llm_called,
      llm_provider: log.llm_provider ?? null,
      llm_is_purchase: log.llm_is_purchase ?? null,
      llm_confidence: log.llm_confidence ?? null,
      llm_merchant_name: log.llm_merchant_name ?? null,
      llm_order_number: log.llm_order_number ?? null,
      learned_sender_matched: !!log.learned_sender_matched,
      learned_sender_match_axis: log.learned_sender_match_axis ?? null,
      final_action: log.final_action,
      merchant_source: log.merchant_source ?? null,
      resolved_merchant: log.resolved_merchant ?? null,
      resolved_order_number: log.resolved_order_number ?? null,
      resolved_total_amount: log.resolved_total_amount ?? null,
      resolved_currency: log.resolved_currency ?? null,
      related_order_id: log.related_order_id ?? null,
      related_review_item_id: log.related_review_item_id ?? null,
      detail: log.detail ?? null,
    };
    const { error } = await supabase.from('email_classifications').insert([payload]);
    if (error) {
      console.warn(`[classifications-store] insert failed: ${error.message}`);
    }
  } catch (err) {
    console.warn(`[classifications-store] insert threw: ${err instanceof Error ? err.message : err}`);
  }
}
