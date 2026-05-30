import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeTrackingNumbers } from './normalize-tracking';

test('rejects empty / whitespace', () => {
  assert.deepEqual(normalizeTrackingNumbers(''), []);
  assert.deepEqual(normalizeTrackingNumbers('   '), []);
  assert.deepEqual(normalizeTrackingNumbers(null), []);
  assert.deepEqual(normalizeTrackingNumbers(undefined), []);
});
test('passes a single valid number through, trimmed', () => {
  assert.deepEqual(normalizeTrackingNumbers('1Z999AA10123456784'), ['1Z999AA10123456784']);
  assert.deepEqual(normalizeTrackingNumbers('  9882676775 '), ['9882676775']);
});
test('splits multi-piece strings on / and ,', () => {
  assert.deepEqual(normalizeTrackingNumbers('7197712620 / 001959496839433548'), ['7197712620', '001959496839433548']);
  assert.deepEqual(normalizeTrackingNumbers('JD0146, JD0147'), ['JD0146', 'JD0147']);
});
test('drops junk pieces that are too short/long after split', () => {
  assert.deepEqual(normalizeTrackingNumbers('12 / 1Z999AA10123456784'), ['1Z999AA10123456784']);
});
test('dedups identical pieces within one string', () => {
  assert.deepEqual(normalizeTrackingNumbers('JD0146 / JD0146'), ['JD0146']);
});
