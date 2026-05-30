import test from 'node:test';
import assert from 'node:assert/strict';
import { isCarrierSender } from './carriers';

test('recognizes known carrier sender domains', () => {
  assert.equal(isCarrierSender('noreply@dhl.com'), true);
  assert.equal(isCarrierSender('track@ups.com'), true);
  assert.equal(isCarrierSender('info@ctt.pt'), true);
});

test('does not flag a merchant as a carrier', () => {
  assert.equal(isCarrierSender('orders@peakdesign.com'), false);
  assert.equal(isCarrierSender('hello@noma.dk'), false);
});
