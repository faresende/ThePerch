import test from 'node:test';
import assert from 'node:assert/strict';

import { buildReviewItem, deriveOrderStatusFromShipments, matchShipmentToOrder } from './matching';
import type { OrderData, ShipmentData } from './types';

function makeOrder(id: string, data: Partial<OrderData> = {}) {
  return {
    id,
    data: {
      merchant_name: 'Amazon',
      normalized_merchant: 'amazon',
      order_number: '112-1234567-7654321',
      order_date: '2026-03-21',
      source_email_ids: [],
      confidence_score: 0.92,
      status: 'ordered' as const,
      ...data,
    },
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
