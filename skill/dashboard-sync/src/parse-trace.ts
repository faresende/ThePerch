/**
 * parse-trace.ts
 *
 * Audit trail for the orders-autopilot pipeline. One ParseTrace per
 * processEmail invocation, accumulated through the pipeline via a
 * ParseTraceBuilder, then written to orders.parse_trace (jsonb).
 *
 * Phase 1 of the corrections-and-rules feedback loop. See
 * docs/superpowers/specs/2026-04-27-orders-corrections-and-rules-design.md.
 *
 * Why an accumulator (not a global / not a return value):
 *   - Local: the builder is a function parameter, fixture tests construct
 *     one and assert on `build()` output without monkey-patching globals.
 *   - Incremental: every decision point in the pipeline (classifier,
 *     merchant resolution, physical/digital, tracking candidates) calls
 *     a `recordX` method as it makes the decision. No "collect everything
 *     up front" requirement.
 *   - Forward-compatible: new decision points add a new `recordX` method
 *     without rewriting downstream consumers — older traces just have
 *     fewer fields.
 */

export const PARSE_TRACE_VERSION = 1 as const;

// Lazy git-sha capture: read once per process from $SCANNER_VERSION env
// var if set, else fall back to a static label. The dashboard-sync
// build pipeline stamps the env var on deploy; tests get the fallback.
const SCANNER_VERSION = process.env.SCANNER_VERSION || 'orders-autopilot@dev';

export interface Tier1Trace {
  matched_keywords: string[];
  confidence: number;
  purchase_score?: number;
  shipping_score?: number;
}

export interface LLMTrace {
  invoked: boolean;
  is_purchase: boolean | null;
  confidence: number | null;
  provider: string | null;
}

export interface LearnedSenderTrace {
  matched: boolean;
  match_axis?: string;       // 'sender_email' | 'sender_domain' | null
  merchant?: string | null;
}

export interface ClassifierTrace {
  tier1: Tier1Trace;
  llm: LLMTrace;
  learned_sender: LearnedSenderTrace;
  short_circuited_by: string | null;       // e.g. 'quoted_prior_order'
  merchant_rule_applied: string | null;    // Phase 2 hook — null in Phase 1
  low_confidence_flagged: boolean;          // Phase 3 hook — true if tier1+llm both <0.5
}

export interface MerchantTrace {
  selected: string | null;
  source: string | null;       // 'learnedSender' | 'known' | 'displayName' | 'domainStem' | 'llm' | ...
  candidates: string[];
}

export interface PhysicalDigitalTrace {
  decision: 'physical' | 'digital';
  signals: {
    shipping_address_in_body: boolean;
    digital_phrases_found: string[];
    tangible_keywords: string[];
  };
}

export interface TrackingCandidateTrace {
  number: string;
  carrier: string | null;
  source: string;              // see ranks in email-classifier.ts (Phase 1.5)
  selected: boolean;
  discarded_reason: string | null;
}

export interface ETACandidateTrace {
  date: string;                // ISO 8601 date (YYYY-MM-DDTHH:mm:ssZ)
  source: string;              // 'body_regex_near_keyword' | 'body_regex_isolated'
  selected: boolean;
  discarded_reason: string | null;
  matched_text: string;        // raw substring captured for debugging
}

export interface ParseTrace {
  version: typeof PARSE_TRACE_VERSION;
  parsed_at: string;
  scanner_version: string;
  classifier: ClassifierTrace;
  merchant: MerchantTrace;
  physical_vs_digital: PhysicalDigitalTrace | null;
  tracking_candidates: TrackingCandidateTrace[];
  /** Phase 1 ETA: candidates extracted from carrier email body. Empty
   *  array when this trace was built during a non-shipping flow (e.g.
   *  purchase confirmation). */
  eta_candidates: ETACandidateTrace[];
  source_email_ids: string[];
}

export class ParseTraceBuilder {
  private readonly trace: ParseTrace;

  constructor(emailId: string) {
    this.trace = {
      version: PARSE_TRACE_VERSION,
      parsed_at: new Date().toISOString(),
      scanner_version: SCANNER_VERSION,
      classifier: {
        tier1: { matched_keywords: [], confidence: 0 },
        llm:   { invoked: false, is_purchase: null, confidence: null, provider: null },
        learned_sender: { matched: false },
        short_circuited_by: null,
        merchant_rule_applied: null,
        low_confidence_flagged: false,
      },
      merchant: { selected: null, source: null, candidates: [] },
      physical_vs_digital: null,
      tracking_candidates: [],
      eta_candidates: [],
      source_email_ids: [emailId],
    };
  }

  recordTier1(t: Partial<Tier1Trace>): void {
    this.trace.classifier.tier1 = { ...this.trace.classifier.tier1, ...t };
  }

  recordLLM(t: Partial<LLMTrace>): void {
    this.trace.classifier.llm = { ...this.trace.classifier.llm, ...t };
  }

  recordLearnedSender(t: Partial<LearnedSenderTrace>): void {
    this.trace.classifier.learned_sender = { ...this.trace.classifier.learned_sender, ...t };
  }

  /** Phase-1 short-circuit — e.g. quoted-prior-order detected. */
  recordShortCircuit(reason: string): void {
    this.trace.classifier.short_circuited_by = reason;
  }

  /** Phase-2 hook — set when applyMerchantRules returns a non-null override. */
  recordMerchantRuleApplied(ruleId: string): void {
    this.trace.classifier.merchant_rule_applied = ruleId;
  }

  /** Phase-3 hook — flag set when tier1 + llm both yield <0.5 confidence. */
  recordLowConfidenceFlag(): void {
    this.trace.classifier.low_confidence_flagged = true;
  }

  recordMerchant(selected: string | null, source: string | null, candidates: string[] = []): void {
    this.trace.merchant = { selected, source, candidates };
  }

  recordPhysicalDigital(t: PhysicalDigitalTrace): void {
    this.trace.physical_vs_digital = t;
  }

  addTrackingCandidate(c: TrackingCandidateTrace): void {
    this.trace.tracking_candidates.push(c);
  }

  addETACandidate(c: ETACandidateTrace): void {
    this.trace.eta_candidates.push(c);
  }

  /** Replace the source_email_ids list. Default constructor seeded with the primary email's id. */
  setSourceEmailIds(ids: string[]): void {
    this.trace.source_email_ids = ids.length > 0 ? ids : this.trace.source_email_ids;
  }

  build(): ParseTrace {
    // Compute the low-confidence flag if not already set by an explicit caller.
    // Done at build time so callers don't have to remember to flip it.
    if (!this.trace.classifier.low_confidence_flagged) {
      const t1 = this.trace.classifier.tier1.confidence;
      const llm = this.trace.classifier.llm;
      const llmFailed = llm.invoked && (llm.confidence === null || llm.confidence < 0.5);
      if (t1 < 0.5 && llmFailed) {
        this.trace.classifier.low_confidence_flagged = true;
      }
    }
    return JSON.parse(JSON.stringify(this.trace)) as ParseTrace;
  }
}
