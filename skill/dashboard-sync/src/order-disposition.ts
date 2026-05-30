/**
 * order-disposition.ts
 *
 * Pure mapper from a classification-cascade verdict to the
 * order-write disposition the live pipeline acts on. Kept side-effect
 * free (no DB, no LLM) so the physical/digital/unsure contract is
 * fully unit-testable without a live database.
 *
 * The contract (order-tracker rework):
 *   - physical → create the order as today, SURFACED
 *                (hidden=false, status='ordered').
 *   - digital  → STILL create the order (retained for audit/learning,
 *                never dropped), but HIDDEN (hidden=true,
 *                status='digital') with hidden_reason = the cascade
 *                reason; shipment creation is skipped by the caller.
 *   - unsure   → do NOT create an order; route to the review queue
 *                (createOrder=false, review=true).
 */

import type { ClassifyResult } from './classification-cascade';

export interface OrderDisposition {
  /** Whether to upsert an order row at all. False only for 'unsure'. */
  createOrder: boolean;
  /** orders.hidden — true keeps the row out of the surfaced tracker. */
  hidden: boolean;
  /** orders.status to write, or null when no order is created. */
  status: 'ordered' | 'digital' | null;
  /** Whether to create a review_item instead of an order. */
  review: boolean;
  /** orders.hidden_reason — the cascade reason for a hidden (digital)
   *  row, else null. */
  hidden_reason: string | null;
}

export function dispositionForClassification(result: ClassifyResult): OrderDisposition {
  switch (result.classification) {
    case 'physical':
      return { createOrder: true, hidden: false, status: 'ordered', review: false, hidden_reason: null };
    case 'digital':
      return { createOrder: true, hidden: true, status: 'digital', review: false, hidden_reason: result.reason };
    case 'unsure':
    default:
      return { createOrder: false, hidden: false, status: null, review: true, hidden_reason: null };
  }
}
