import { normalizeMerchantName } from './orders';
import type { OrderData, ReviewItemData, ShipmentData } from './types';

export interface OrderRecordCandidate {
  id: string;
  data: OrderData;
}

export interface ShipmentRecordCandidate {
  id: string;
  data: ShipmentData;
}

export interface ShipmentMatchResult {
  matched_order_id?: string;
  matched_shipment_id?: string;
  review_item?: ReviewItemData;
}

export function buildReviewItem(input: {
  type: ReviewItemData['type'];
  reason: string;
  suggested_action: string;
  confidence_score: number;
  related_order_id?: string;
  related_shipment_id?: string;
}): ReviewItemData {
  return {
    type: input.type,
    reason: input.reason,
    suggested_action: input.suggested_action,
    confidence_score: input.confidence_score,
    related_order_id: input.related_order_id,
    related_shipment_id: input.related_shipment_id,
  };
}

export function matchShipmentToOrder(input: {
  shipment: ShipmentData;
  existing_orders: OrderRecordCandidate[];
  existing_shipments: ShipmentRecordCandidate[];
}): ShipmentMatchResult {
  const trackingNumber = normalizeTracking(input.shipment.tracking_number);
  const matchedShipment = trackingNumber
    ? input.existing_shipments.find((shipment) => normalizeTracking(shipment.data.tracking_number) === trackingNumber)
    : undefined;

  if (matchedShipment) {
    return { matched_shipment_id: matchedShipment.id };
  }

  if (input.shipment.order_id) {
    const exactOrder = input.existing_orders.find((order) => order.id === input.shipment.order_id);
    if (exactOrder) {
      return { matched_order_id: exactOrder.id };
    }
  }

  const normalizedMerchant =
    input.shipment.normalized_merchant ||
    (input.shipment.merchant_name ? normalizeMerchantName(input.shipment.merchant_name) : '');
  const orderNumber = input.shipment.order_number?.trim();

  if (normalizedMerchant && orderNumber) {
    const exactMatches = input.existing_orders.filter(
      (order) =>
        order.data.normalized_merchant === normalizedMerchant &&
        order.data.order_number?.trim() === orderNumber,
    );

    if (exactMatches.length === 1) {
      return { matched_order_id: exactMatches[0].id };
    }

    if (exactMatches.length > 1) {
      return {
        review_item: buildReviewItem({
          type: 'ambiguous_order_match',
          reason: `Multiple orders matched ${normalizedMerchant} ${orderNumber}.`,
          suggested_action: 'Review the candidate orders before linking this shipment.',
          confidence_score: 0.36,
          related_order_id: exactMatches[0].id,
        }),
      };
    }
  }

  if (normalizedMerchant && !orderNumber) {
    const merchantMatches = input.existing_orders.filter(
      (order) => order.data.normalized_merchant === normalizedMerchant,
    );

    if (merchantMatches.length > 1) {
      return {
        review_item: buildReviewItem({
          type: 'ambiguous_order_match',
          reason: `Shipment matched ${merchantMatches.length} orders for ${normalizedMerchant} but had no order number.`,
          suggested_action: 'Review matching orders and attach tracking manually.',
          confidence_score: 0.31,
          related_order_id: merchantMatches[0].id,
        }),
      };
    }
  }

  // ── Probabilistic matching: try soft signals before giving up ──
  const scored = scoreAllOrders(input.shipment, input.existing_orders);
  if (scored.length > 0) {
    const top = scored[0];
    const runnerUp = scored.length > 1 ? scored[1] : undefined;
    const isUnambiguous = !runnerUp || top.score - runnerUp.score >= AMBIGUITY_GAP;

    if (top.score >= SOFT_MATCH_THRESHOLD && isUnambiguous) {
      return {
        matched_order_id: top.order.id,
        review_item: buildReviewItem({
          type: 'low_confidence_match',
          reason: `Soft-matched to order ${top.order.data.order_number ?? top.order.id} (score ${top.score.toFixed(2)}: ${top.reasons.join(', ')}).`,
          suggested_action: 'Verify this link is correct; unlink if wrong.',
          confidence_score: top.score,
          related_order_id: top.order.id,
        }),
      };
    }

    if (top.score >= REVIEW_THRESHOLD) {
      return {
        review_item: buildReviewItem({
          type: 'low_confidence_match',
          reason: `Possible match to order ${top.order.data.order_number ?? top.order.id} (score ${top.score.toFixed(2)}: ${top.reasons.join(', ')}), but confidence too low to auto-link.`,
          suggested_action: 'Review the candidate order and link manually if correct.',
          confidence_score: top.score,
          related_order_id: top.order.id,
        }),
      };
    }
  }

  if (trackingNumber) {
    return {
      review_item: buildReviewItem({
        type: 'missing_order_for_tracking',
        reason: `Tracking ${trackingNumber} could not be linked to any known order.`,
        suggested_action: 'Create a standalone shipment and queue this for order review.',
        confidence_score: 0.58,
      }),
    };
  }

  return {
    review_item: buildReviewItem({
      type: 'missing_tracking_for_order',
      reason: 'Shipment-like event did not contain a usable tracking number.',
      suggested_action: 'Keep the commerce item detached until tracking is available.',
      confidence_score: 0.24,
    }),
  };
}

export function deriveOrderStatusFromShipments(shipments: ShipmentData[]): OrderData['status'] {
  if (shipments.length === 0) {
    return 'ordered';
  }

  const statuses = shipments.map((shipment) => shipment.status);

  if (statuses.some((status) => status === 'exception')) {
    return 'issue';
  }

  if (statuses.every((status) => status === 'delivered')) {
    return 'delivered';
  }

  const shippedLikeCount = statuses.filter((status) =>
    ['label_created', 'in_transit', 'out_for_delivery', 'delivered'].includes(status),
  ).length;
  const deliveredCount = statuses.filter((status) => status === 'delivered').length;

  if (deliveredCount > 0 && deliveredCount < shipments.length) {
    return 'shipped_partial';
  }

  if (shippedLikeCount > 0) {
    return 'shipped';
  }

  return 'processing';
}

function normalizeTracking(value?: string): string {
  return value?.trim().toUpperCase() || '';
}

// ── Probabilistic / soft matching ──────────────────────────────

/** Auto-link threshold: must be unambiguous AND above this score */
const SOFT_MATCH_THRESHOLD = 0.55;
/** Below this we don't even surface a review item — too noisy */
const REVIEW_THRESHOLD = 0.40;
/** Minimum gap between #1 and #2 to count as unambiguous */
const AMBIGUITY_GAP = 0.15;

interface ScoredOrder {
  order: OrderRecordCandidate;
  score: number;
  reasons: string[];
}

/**
 * Score every candidate order against a shipment using soft signals.
 * Returns only orders with score > 0, sorted descending.
 *
 * Signals (all additive, capped at 1.0):
 *  - Merchant substring containment: 0.30
 *  - Partial order-number overlap (≥6 shared chars): 0.25
 *  - Order date proximity (within 14 days of shipment): 0.20
 *  - Order is still active (not delivered/cancelled): 0.10
 */
export function scoreAllOrders(
  shipment: ShipmentData,
  orders: OrderRecordCandidate[],
): ScoredOrder[] {
  const shipMerchant =
    shipment.normalized_merchant ||
    (shipment.merchant_name ? normalizeMerchantName(shipment.merchant_name) : '');
  const shipOrderNum = (shipment.order_number ?? '').trim().toUpperCase();
  const shipDate = parseLooseDate(shipment.shipped_at);

  const results: ScoredOrder[] = [];

  for (const order of orders) {
    let score = 0;
    const reasons: string[] = [];

    // 1. Merchant substring containment (both directions)
    const orderMerchant = order.data.normalized_merchant ?? '';
    if (shipMerchant && orderMerchant) {
      if (shipMerchant.includes(orderMerchant) || orderMerchant.includes(shipMerchant)) {
        score += 0.30;
        reasons.push('merchant-substring');
      }
    }

    // 2. Partial order-number overlap (shared character sequence ≥ 8)
    //    Raised from 6 to 8 to avoid coincidental short digit matches like "123456".
    const orderNum = (order.data.order_number ?? '').trim().toUpperCase();
    if (shipOrderNum && orderNum) {
      const overlap = longestCommonSubstring(shipOrderNum, orderNum);
      if (overlap >= 8) {
        score += 0.25;
        reasons.push(`order-num-overlap(${overlap})`);
      }
    }

    // 3. Order date proximity
    const orderDate = parseLooseDate(order.data.order_date);
    if (shipDate && orderDate) {
      const daysDiff = Math.abs(shipDate.getTime() - orderDate.getTime()) / (1000 * 60 * 60 * 24);
      if (daysDiff <= 14) {
        score += 0.20;
        reasons.push(`date-proximity(${Math.round(daysDiff)}d)`);
      }
    }

    // 4. Active order bonus (not yet delivered or cancelled)
    if (!['delivered', 'cancelled'].includes(order.data.status)) {
      score += 0.10;
      reasons.push('active-order');
    }

    if (score > 0) {
      results.push({ order, score: Math.min(score, 1.0), reasons });
    }
  }

  return results.sort((a, b) => b.score - a.score);
}

/** Parse a date string loosely; returns undefined on failure */
function parseLooseDate(value?: string | null): Date | undefined {
  if (!value) return undefined;
  const d = new Date(value);
  return isNaN(d.getTime()) ? undefined : d;
}

/** Length of the longest common substring between two strings */
function longestCommonSubstring(a: string, b: string): number {
  if (!a || !b) return 0;
  const shorter = a.length <= b.length ? a : b;
  const longer = a.length > b.length ? a : b;
  let best = 0;
  for (let i = 0; i < shorter.length; i++) {
    for (let j = i + best + 1; j <= shorter.length; j++) {
      if (longer.includes(shorter.slice(i, j))) {
        best = j - i;
      } else {
        break;
      }
    }
  }
  return best;
}
