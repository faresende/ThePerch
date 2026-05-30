import test from 'node:test';
import assert from 'node:assert/strict';

import type {
  OrderData,
  ShipmentData,
  ReviewItemData,
  RecordType,
  RecordCategory,
} from './types';
import {
  extractOrderCandidate,
  extractShipmentCandidate,
  normalizeMerchantName,
} from './orders';
import { shipmentRowsForTracking, isPollable } from './orders-autopilot';
import { parseClassificationFromLLM } from './llm-extractor';
import { ruleFromReviewAnswer } from './merchant-rules';

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
  assert.equal(order.source_email_ids?.length, 1);
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

test('normalizeMerchantName lowercases and strips common suffix noise', () => {
  assert.equal(normalizeMerchantName('Amazon EU S.a r.l.'), 'amazon');
  assert.equal(normalizeMerchantName('ZARA Portugal, Lda.'), 'zara portugal');
});

test('extractOrderCandidate parses purchase confirmation text', () => {
  const candidate = extractOrderCandidate(`
    Your Amazon order has been placed.
    Order number: 112-1234567-7654321
    Total: EUR 42.50
    Merchant: Amazon EU S.a r.l.
    Ordered on 2026-03-21
  `);

  assert.ok(candidate);
  assert.equal(candidate?.merchant_name, 'Amazon EU S.a r.l.');
  assert.equal(candidate?.normalized_merchant, 'amazon');
  assert.equal(candidate?.order_number, '112-1234567-7654321');
  assert.equal(candidate?.total_amount, 42.5);
  assert.equal(candidate?.currency, 'EUR');
});

test('extractShipmentCandidate parses shipment update text with tracking', () => {
  const candidate = extractShipmentCandidate(`
    UPS shipment update
    Tracking number 1Z999AA10123456784
    Order number: 112-1234567-7654321
    Status: out for delivery
    Merchant: Amazon EU S.a r.l.
    Carrier: UPS
  `);

  assert.ok(candidate);
  assert.equal(candidate?.tracking_number, '1Z999AA10123456784');
  assert.equal(candidate?.carrier, 'UPS');
  assert.equal(candidate?.order_number, '112-1234567-7654321');
  assert.equal(candidate?.normalized_merchant, 'amazon');
  assert.equal(candidate?.status, 'out_for_delivery');
});

test('extractOrderCandidate does not invent an order from shipment-only text', () => {
  const candidate = extractOrderCandidate(`
    DHL tracking 00340434161234567890 is in transit.
    Expected delivery tomorrow.
  `);

  assert.equal(candidate, null);
});

test('a multi-piece tracking string yields N shipment rows, deduped', () => {
  const rows = shipmentRowsForTracking('7197712620 / 001959496839433548', 'DHL');
  assert.equal(rows.length, 2);
  assert.deepEqual(rows.map(r => r.tracking_number), ['7197712620', '001959496839433548']);
});
test('an empty tracking string yields zero shipment rows (no phantom)', () => {
  assert.deepEqual(shipmentRowsForTracking('', 'DHL'), []);
});

test('parses physical/digital/confidence from LLM JSON', () => {
  assert.deepEqual(parseClassificationFromLLM('{"classification":"physical","confidence":0.91}'), { classification: 'physical', confidence: 0.91 });
  assert.deepEqual(parseClassificationFromLLM('{"classification":"digital","confidence":0.4}'), { classification: 'digital', confidence: 0.4 });
});
test('falls back to unsure on unparseable LLM output', () => {
  assert.deepEqual(parseClassificationFromLLM('not json'), { classification: 'unsure', confidence: 0 });
});

test('maps a review answer to a merchant_rule spec on the most specific signal', () => {
  assert.deepEqual(ruleFromReviewAnswer({ senderEmail: 'orders@peakdesign.com', normalizedMerchant: 'peak design' }, 'yes_track'),
    { match_kind: 'sender_email', match_value: 'orders@peakdesign.com', action: 'always_physical' });
});
test('no_package answer writes skip_purchase', () => {
  assert.deepEqual(ruleFromReviewAnswer({ senderEmail: null, normalizedMerchant: 'cleancloud' }, 'no_package'),
    { match_kind: 'normalized_merchant', match_value: 'cleancloud', action: 'skip_purchase' });
});
test('bought_but_digital answer writes always_digital', () => {
  assert.deepEqual(ruleFromReviewAnswer({ senderEmail: 'do@apple.com', normalizedMerchant: 'apple' }, 'bought_but_digital'),
    { match_kind: 'sender_email', match_value: 'do@apple.com', action: 'always_digital' });
});

test('pollable = valid tracking, non-terminal status', () => {
  assert.equal(isPollable({ tracking_number: '1Z999AA10123456784', status: 'in_transit' }), true);
  assert.equal(isPollable({ tracking_number: '', status: 'in_transit' }), false);
  assert.equal(isPollable({ tracking_number: '1Z999AA10123456784', status: 'delivered' }), false);
  assert.equal(isPollable({ tracking_number: '7197712620 / 0019', status: 'in_transit' }), false);
});
