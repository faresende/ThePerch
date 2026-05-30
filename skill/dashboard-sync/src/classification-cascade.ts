/**
 * classification-cascade.ts
 *
 * The order-tracker rework's classification cascade. Every inbound
 * commerce email runs through this so ONLY tangible packages surface in
 * the tracker. Layers run cheapest-and-most-certain first; each layer
 * that fires short-circuits the rest:
 *
 *   1. carrier short-circuit   — sender is a known parcel carrier
 *                                (DHL/UPS/CTT…) → physical, conf 0.99.
 *   2. learned merchant_rules  — a rule the user taught us via the
 *                                review loop (always_physical /
 *                                always_digital / skip_purchase).
 *   3. hard-category excludes  — sender can never ship a package
 *                                (airline/restaurant/SaaS/financial…)
 *                                → digital, conf 0.95.
 *   4. repurposed LLM          — physical/digital/unsure + confidence.
 *   5. confidence banding      — high-conf LLM verdicts pass through;
 *                                low-conf passes through with a flag;
 *                                the mid band lands in 'unsure' for the
 *                                human review queue.
 *
 * Pure orchestrator: the only side-effecting concerns (DB rule lookup,
 * the LLM call) are injected via `CascadeDeps`, so this module has ZERO
 * Supabase / network imports and its tests stay deterministic.
 */

import { isCarrierSender } from './carriers';
import { hardCategoryExclude } from './physical-vs-digital';

export type Classification = 'physical' | 'digital' | 'unsure';

export interface ClassifyInput {
  subject: string;
  body: string;
  senderEmail?: string;
  senderName?: string;
}

export interface ClassifyResult {
  classification: Classification;
  confidence: number;
  /** Which cascade layer produced the verdict (telemetry + debugging). */
  reason: string;
}

export interface CascadeDeps {
  /** Look up a learned merchant_rule action, or null when none matches. */
  lookupRule: (input: ClassifyInput) => Promise<string | null>;
  /** Run the repurposed LLM classifier. */
  llm: (input: ClassifyInput) => Promise<{ classification: Classification; confidence: number }>;
}

// LLM confidence band edges. Below LOW: trust the low-confidence verdict
// as-is (flagged). Between LOW and HIGH: route to 'unsure' for review.
// At or above HIGH: accept the LLM's physical/digital verdict.
const UNSURE_LOW = 0.45;
const UNSURE_HIGH = 0.75;

export async function classifyForTracking(input: ClassifyInput, deps: CascadeDeps): Promise<ClassifyResult> {
  // 1. Carrier short-circuit — a parcel carrier only ever emails about
  //    a tangible package in transit.
  if (isCarrierSender(input.senderEmail)) {
    return { classification: 'physical', confidence: 0.99, reason: 'carrier-sender' };
  }

  // 2. Learned merchant_rules — the user already taught us this sender.
  const rule = await deps.lookupRule(input);
  if (rule === 'always_physical') {
    return { classification: 'physical', confidence: 1, reason: 'learned-rule' };
  }
  if (rule === 'always_digital' || rule === 'skip_purchase') {
    return { classification: 'digital', confidence: 1, reason: 'learned-rule' };
  }

  // 3. Hard-category excludes — senders that can never ship a package.
  const cat = hardCategoryExclude(input.senderEmail);
  if (cat) {
    return { classification: 'digital', confidence: 0.95, reason: `hard-category:${cat}` };
  }

  // 4. Repurposed LLM.
  const llm = await deps.llm(input);

  // 5. Confidence banding.
  if (llm.classification === 'physical' && llm.confidence >= UNSURE_HIGH) {
    return { classification: 'physical', confidence: llm.confidence, reason: 'llm-high' };
  }
  if (llm.classification === 'digital' && llm.confidence >= UNSURE_HIGH) {
    return { classification: 'digital', confidence: llm.confidence, reason: 'llm-high' };
  }
  if (llm.confidence < UNSURE_LOW) {
    return { classification: llm.classification, confidence: llm.confidence, reason: 'llm-lowconf' };
  }
  return { classification: 'unsure', confidence: llm.confidence, reason: 'llm-midband' };
}
