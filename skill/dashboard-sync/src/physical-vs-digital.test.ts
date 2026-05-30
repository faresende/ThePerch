import test from 'node:test';
import assert from 'node:assert/strict';
import { hardCategoryExclude } from './physical-vs-digital';

test('excludes airlines, restaurants, SaaS, brokerage by sender domain', () => {
  assert.equal(hardCategoryExclude('booking@flytap.com'), 'airline');
  assert.equal(hardCategoryExclude('reservations@noma.dk'), 'restaurant');
  assert.equal(hardCategoryExclude('billing@godaddy.com'), 'domains');
  assert.equal(hardCategoryExclude('statements@schwab.com'), 'financial');
  assert.equal(hardCategoryExclude('receipts@cleancloud.com'), 'service');
});

test('returns null for a real physical merchant', () => {
  assert.equal(hardCategoryExclude('orders@peakdesign.com'), null);
  assert.equal(hardCategoryExclude('shop@notino.com'), null);
});
