import test from 'node:test';
import assert from 'node:assert/strict';

import type {
  OrderData,
  ShipmentData,
  ReviewItemData,
  RecordType,
  RecordCategory,
} from './types';

test('canonical commerce types are supported', () => {
  const orderType: RecordType = 'order';
  const shipmentType: RecordType = 'shipment';
  const reviewType: RecordType = 'review_item';
  const commerceCategory: RecordCategory = 'commerce';

  assert.equal(orderType, 'order');
  assert.equal(shipmentType, 'shipment');
  assert.equal(reviewType, 'review_item');
  assert.equal(commerceCategory, 'commerce');
});

test('OrderData captures normalized order identity and confidence', () => {
  const order: OrderData = {
    merchant_name: 'Amazon',
    normalized_merchant: 'amazon',
    order_number: '112-1234567-7654321',
    order_date: '2026-03-21',
    total_amount: 42.5,
    currency: 'EUR',
    source_email_ids: ['gmail:abc123'],
    confidence_score: 0.96,
    status: 'ordered',
  };

  assert.equal(order.normalized_merchant, 'amazon');
  assert.equal(order.status, 'ordered');
  assert.equal(order.source_email_ids.length, 1);
});

test('ShipmentData captures tracking, provider, and confidence', () => {
  const shipment: ShipmentData = {
    order_id: 'order_123',
    tracking_number: '1Z999AA10123456784',
    carrier: 'UPS',
    provider: '17track',
    status: 'in_transit',
    latest_checkpoint: 'Departed facility',
    shipped_at: '2026-03-21T09:30:00Z',
    delivered_at: undefined,
    source_email_ids: ['gmail:def456'],
    confidence_score: 0.91,
  };

  assert.equal(shipment.provider, '17track');
  assert.equal(shipment.status, 'in_transit');
});

test('ReviewItemData captures ambiguous cases without unsafe auto-merge', () => {
  const reviewItem: ReviewItemData = {
    type: 'ambiguous_order_match',
    reason: 'Two candidate orders matched same merchant and close timestamps',
    suggested_action: 'Review and confirm which order owns tracking 1Z999AA10123456784',
    confidence_score: 0.42,
    related_order_id: 'order_123',
    related_shipment_id: 'shipment_123',
  };

  assert.equal(reviewItem.type, 'ambiguous_order_match');
  assert.equal(reviewItem.related_shipment_id, 'shipment_123');
});
