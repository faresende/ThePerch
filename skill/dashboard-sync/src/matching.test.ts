import test from 'node:test';
import assert from 'node:assert/strict';

import { buildReviewItem, deriveOrderStatusFromShipments, matchShipmentToOrder, scoreAllOrders } from './matching';
import type { OrderData, ShipmentData } from './types';

function makeOrder(id: string, data: Partial<OrderData> = {}): { id: string; data: OrderData } {
  return {
    id,
    data: {
      merchant_name: 'Amazon',
      normalized_merchant: 'amazon',
      order_number: '112-1234567-7654321',
      order_date: '2026-03-21',
      currency: 'USD',
      source_email_ids: [],
      confidence_score: 0.92,
      status: 'ordered' as const,
      ...data,
    } as OrderData,
  };
}

function makeShipment(data: Partial<ShipmentData> = {}): ShipmentData {
  return {
    tracking_number: '1Z999AA10123456784',
    carrier: 'UPS',
    provider: 'email',
    status: 'in_transit',
    source_email_ids: [],
    confidence_score: 0.88,
    ...data,
  };
}

test('matchShipmentToOrder links by exact merchant and order number', () => {
  const result = matchShipmentToOrder({
    shipment: makeShipment({
      merchant_name: 'Amazon EU S.a r.l.',
      normalized_merchant: 'amazon',
      order_number: '112-1234567-7654321',
    }),
    existing_orders: [makeOrder('order_1')],
    existing_shipments: [],
  });

  assert.equal(result.matched_order_id, 'order_1');
  assert.equal(result.review_item, undefined);
});

test('matchShipmentToOrder links shipment updates by exact tracking number first', () => {
  const result = matchShipmentToOrder({
    shipment: makeShipment(),
    existing_orders: [makeOrder('order_1')],
    existing_shipments: [{ id: 'shipment_1', data: makeShipment() }],
  });

  assert.equal(result.matched_shipment_id, 'shipment_1');
  assert.equal(result.matched_order_id, undefined);
});

test('merchant-only ambiguity produces a review item instead of auto-linking', () => {
  const result = matchShipmentToOrder({
    shipment: makeShipment({
      merchant_name: 'Amazon',
      normalized_merchant: 'amazon',
      order_number: undefined,
    }),
    existing_orders: [
      makeOrder('order_1', { order_number: '112-1234567-7654321' }),
      makeOrder('order_2', { order_number: '112-7654321-1234567' }),
    ],
    existing_shipments: [],
  });

  assert.equal(result.matched_order_id, undefined);
  assert.equal(result.review_item?.type, 'ambiguous_order_match');
});

test('missing order with valid tracking yields a review item for standalone shipment flow', () => {
  const result = matchShipmentToOrder({
    shipment: makeShipment({
      merchant_name: 'Nike',
      normalized_merchant: 'nike',
      order_number: 'NIKE-123456',
    }),
    existing_orders: [makeOrder('order_1')],
    existing_shipments: [],
  });

  assert.equal(result.matched_order_id, undefined);
  assert.equal(result.review_item?.type, 'missing_order_for_tracking');
});

test('deriveOrderStatusFromShipments marks partial and delivered states deterministically', () => {
  assert.equal(
    deriveOrderStatusFromShipments([
      makeShipment({ status: 'delivered' }),
      makeShipment({ tracking_number: 'TRACK2', status: 'in_transit' }),
    ]),
    'shipped_partial',
  );

  assert.equal(
    deriveOrderStatusFromShipments([
      makeShipment({ status: 'delivered' }),
      makeShipment({ tracking_number: 'TRACK2', status: 'delivered' }),
    ]),
    'delivered',
  );
});

// ── Probabilistic matching tests ──

test('scoreAllOrders: merchant substring match scores 0.30', () => {
  const shipment = makeShipment({
    merchant_name: 'Amazon EU',
    normalized_merchant: 'amazon eu',
    order_number: undefined,
  });
  const orders = [
    makeOrder('order_1', { normalized_merchant: 'amazon', status: 'delivered' }),
  ];
  const scored = scoreAllOrders(shipment, orders);
  assert.equal(scored.length, 1);
  assert.ok(scored[0].reasons.includes('merchant-substring'));
  // merchant-substring (0.30) only — order is delivered so no active bonus
  assert.ok(scored[0].score >= 0.29 && scored[0].score <= 0.31);
});

test('scoreAllOrders: partial order number overlap scores when ≥8 chars shared', () => {
  const shipment = makeShipment({
    merchant_name: 'Nike',
    normalized_merchant: 'nike',
    order_number: 'NIKE-12345678-XYZ',
  });
  const orders = [
    makeOrder('order_1', {
      merchant_name: 'Nike',
      normalized_merchant: 'nike',
      order_number: 'NIKE-12345678-ABC',
      status: 'ordered',
    }),
  ];
  const scored = scoreAllOrders(shipment, orders);
  assert.equal(scored.length, 1);
  assert.ok(scored[0].reasons.some((r) => r.startsWith('order-num-overlap')));
});

test('scoreAllOrders: no score when merchants are completely different', () => {
  const shipment = makeShipment({
    merchant_name: 'Apple',
    normalized_merchant: 'apple',
    order_number: 'AP-999',
  });
  const orders = [
    makeOrder('order_1', {
      merchant_name: 'Nike',
      normalized_merchant: 'nike',
      order_number: 'NK-111',
      status: 'delivered',
    }),
  ];
  const scored = scoreAllOrders(shipment, orders);
  // No merchant overlap, no order number overlap (< 6 chars), no date, delivered → 0
  assert.equal(scored.length, 0);
});

test('scoreAllOrders: date proximity adds 0.20 when within 14 days', () => {
  const shipment = makeShipment({
    merchant_name: 'Amazon',
    normalized_merchant: 'amazon',
    shipped_at: '2026-04-10',
  });
  const orders = [
    makeOrder('order_1', { normalized_merchant: 'amazon', order_date: '2026-04-05', status: 'ordered' }),
    makeOrder('order_2', { normalized_merchant: 'amazon', order_date: '2026-01-01', status: 'ordered' }),
  ];
  const scored = scoreAllOrders(shipment, orders);
  // Both get merchant (0.30) + active (0.10), but only order_1 gets date proximity (0.20)
  assert.equal(scored[0].order.id, 'order_1');
  assert.ok(scored[0].score > scored[1].score);
  assert.ok(scored[0].reasons.some((r) => r.startsWith('date-proximity')));
});

test('matchShipmentToOrder: soft match auto-links with review item when score ≥ 0.55 and unambiguous', () => {
  const result = matchShipmentToOrder({
    shipment: makeShipment({
      merchant_name: 'Amazon EU',
      normalized_merchant: 'amazon eu',
      order_number: 'AMZ-112233-XXAA',
      shipped_at: '2026-04-01',
    }),
    existing_orders: [
      makeOrder('order_1', {
        normalized_merchant: 'amazon',
        order_number: 'AMZ-112233-YYBB',
        order_date: '2026-03-28',
        status: 'ordered',
      }),
    ],
    existing_shipments: [],
  });

  // merchant-substring(0.30) + order-num-overlap(0.25) + date-proximity(0.20) + active(0.10) = 0.85
  assert.equal(result.matched_order_id, 'order_1');
  assert.equal(result.review_item?.type, 'low_confidence_match');
});

test('matchShipmentToOrder: soft match does NOT auto-link when two candidates are close in score', () => {
  const result = matchShipmentToOrder({
    shipment: makeShipment({
      merchant_name: 'Amazon',
      normalized_merchant: 'amazon',
      order_number: undefined,
      shipped_at: '2026-04-01',
    }),
    existing_orders: [
      makeOrder('order_1', {
        normalized_merchant: 'amazon',
        order_date: '2026-03-28',
        status: 'ordered',
      }),
      makeOrder('order_2', {
        normalized_merchant: 'amazon',
        order_date: '2026-03-30',
        status: 'ordered',
      }),
    ],
    existing_shipments: [],
  });

  // Both score merchant(0.30) + date(0.20) + active(0.10) = 0.60 — ambiguous (gap < 0.15)
  // Should NOT auto-link, but should produce a review item
  assert.equal(result.matched_order_id, undefined);
  assert.ok(result.review_item != null);
});

test('matchShipmentToOrder: completely unrelated shipment falls through to orphan review', () => {
  const result = matchShipmentToOrder({
    shipment: makeShipment({
      merchant_name: 'Zalando',
      normalized_merchant: 'zalando',
      order_number: 'ZAL-999',
    }),
    existing_orders: [
      makeOrder('order_1', {
        merchant_name: 'Apple',
        normalized_merchant: 'apple',
        order_number: 'AP-111',
        status: 'delivered',
      }),
    ],
    existing_shipments: [],
  });

  // No signals match → falls through to missing_order_for_tracking
  assert.equal(result.matched_order_id, undefined);
  assert.equal(result.review_item?.type, 'missing_order_for_tracking');
});

test('matchShipmentToOrder: weak score below review threshold produces orphan, not low_confidence_match', () => {
  const result = matchShipmentToOrder({
    shipment: makeShipment({
      merchant_name: 'Amazon',
      normalized_merchant: 'amazon',
      order_number: 'TOTALLY-DIFFERENT',
    }),
    existing_orders: [
      makeOrder('order_1', {
        merchant_name: 'Amazon Prime',
        normalized_merchant: 'amazon prime',
        order_number: 'AP-999999',
        status: 'delivered',
      }),
    ],
    existing_shipments: [],
  });

  // merchant-substring(0.30) only — delivered so no active bonus, no date, no order overlap
  // 0.30 < REVIEW_THRESHOLD(0.35) → should fall through to orphan
  assert.equal(result.review_item?.type, 'missing_order_for_tracking');
});

test('buildReviewItem preserves related IDs when provided', () => {
  const review = buildReviewItem({
    type: 'missing_order_for_tracking',
    reason: 'Tracking could not be linked',
    suggested_action: 'Review manually',
    confidence_score: 0.5,
    related_order_id: 'order_1',
    related_shipment_id: 'shipment_1',
  });

  assert.equal(review.related_order_id, 'order_1');
  assert.equal(review.related_shipment_id, 'shipment_1');
});
