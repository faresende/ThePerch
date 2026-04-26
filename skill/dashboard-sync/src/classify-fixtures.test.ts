/**
 * classify-fixtures.test.ts
 *
 * Regression tests for the email classifier against real-world email
 * fixtures captured from JMAP. The fixtures live in
 * `test/fixtures/orders/*.json` (should classify as
 * purchase_confirmation) and `test/fixtures/rejections/*.json` (should
 * classify as `other`).
 *
 * Refresh fixtures with:
 *     python3 test/fixtures/fetch_fixtures.py
 *
 * Each fixture has the shape:
 *   {
 *     "label": "hardgraft-hgmc20117325",
 *     "input": { "subject", "body", "senderEmail", "senderName" },
 *     "expected": {
 *       "type": "purchase_confirmation" | "shipping_notification" | "other",
 *       "merchant": "Hardgraft",                     // optional
 *       "order_number": "HGMC20117325"               // optional
 *     }
 *   }
 *
 * The runner exercises only the pure functions (`classifyEmail`,
 * `extractOrderFields`) — no Supabase / LLM / network. That keeps the
 * test deterministic and fast.
 */

import { test } from 'node:test';
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { classifyEmail, extractOrderFields } from './email-classifier';

interface Fixture {
  label: string;
  source_email_id: string;
  input: {
    subject: string;
    sender: string;
    senderName?: string;
    senderEmail?: string;
    body: string;
  };
  expected: {
    type: 'purchase_confirmation' | 'shipping_notification' | 'other';
    merchant?: string;
    order_number?: string;
  };
}

const FIXTURES_ROOT = path.join(__dirname, '..', 'test', 'fixtures');

function loadFixtures(bucket: 'orders' | 'rejections'): Fixture[] {
  const dir = path.join(FIXTURES_ROOT, bucket);
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter(f => f.endsWith('.json'))
    .map(f => JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')) as Fixture);
}

const orderFixtures = loadFixtures('orders');
const rejectionFixtures = loadFixtures('rejections');

// ─── orders/ — every one of these MUST classify as a purchase and
//                extract the right merchant + order number. ───────────
for (const fx of orderFixtures) {
  test(`fixture orders/${fx.label} → ${fx.expected.type}`, () => {
    const senderEmail = fx.input.senderEmail || fx.input.sender;
    const senderName = fx.input.senderName || '';

    const result = classifyEmail(
      fx.input.subject,
      fx.input.body,
      senderEmail,
      { senderName },
    );
    assert.equal(result.type, fx.expected.type,
      `expected type ${fx.expected.type}, got ${result.type} (purchaseScore=${result.purchaseScore.toFixed(2)}, shippingScore=${result.shippingScore.toFixed(2)})`);

    if (fx.expected.merchant || fx.expected.order_number) {
      const fields = extractOrderFields(
        fx.input.subject, fx.input.body, senderEmail,
        fx.source_email_id, senderName,
      );
      if (fx.expected.merchant) {
        assert.equal(fields.merchantName, fx.expected.merchant,
          `expected merchant ${fx.expected.merchant!}, got ${fields.merchantName} (source=${fields.merchantSource})`);
      }
      if (fx.expected.order_number) {
        assert.equal(fields.orderNumber, fx.expected.order_number,
          `expected order_number ${fx.expected.order_number!}, got ${fields.orderNumber}`);
      }
    }
  });
}

// ─── rejections/ — should NOT classify as a purchase. We require
//                  type !== 'purchase_confirmation'; further demotion
//                  to 'other' is not strictly required (a misclass to
//                  shipping_notification with no tracking number ends
//                  up in the review queue, which is acceptable). ─────
for (const fx of rejectionFixtures) {
  test(`fixture rejections/${fx.label} → ${fx.expected.type}`, () => {
    const senderEmail = fx.input.senderEmail || fx.input.sender;
    const senderName = fx.input.senderName || '';

    const result = classifyEmail(
      fx.input.subject,
      fx.input.body,
      senderEmail,
      { senderName },
    );
    assert.notEqual(result.type, 'purchase_confirmation',
      `${fx.label} was incorrectly classified as a purchase (purchaseScore=${result.purchaseScore.toFixed(2)}, conf=${result.confidence.toFixed(2)}, matched=${result.matchedKeywords.join(',')})`);
    assert.equal(result.type, fx.expected.type,
      `expected type ${fx.expected.type}, got ${result.type}`);
  });
}

// ─── Sanity check — the fixture files exist. ──────────────────────
test('fixture files exist', () => {
  assert.ok(orderFixtures.length > 0,
    'no order fixtures found — run python3 test/fixtures/fetch_fixtures.py');
  assert.ok(rejectionFixtures.length > 0,
    'no rejection fixtures found — run python3 test/fixtures/fetch_fixtures.py');
});
