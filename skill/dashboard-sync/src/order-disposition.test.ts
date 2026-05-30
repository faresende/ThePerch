import test from 'node:test';
import assert from 'node:assert/strict';

import { dispositionForClassification } from './order-disposition';
import type { ClassifyResult } from './classification-cascade';

test('physical → create a surfaced order', () => {
  const result: ClassifyResult = { classification: 'physical', confidence: 0.99, reason: 'carrier-sender' };
  assert.deepEqual(dispositionForClassification(result), {
    createOrder: true,
    hidden: false,
    status: 'ordered',
    review: false,
    hidden_reason: null,
  });
});

test('digital → create a hidden order stamped with the cascade reason', () => {
  const result: ClassifyResult = { classification: 'digital', confidence: 0.95, reason: 'hard-category:airline' };
  assert.deepEqual(dispositionForClassification(result), {
    createOrder: true,
    hidden: true,
    status: 'digital',
    review: false,
    hidden_reason: 'hard-category:airline',
  });
});

test('unsure → no order, route to review', () => {
  const result: ClassifyResult = { classification: 'unsure', confidence: 0.6, reason: 'llm-midband' };
  assert.deepEqual(dispositionForClassification(result), {
    createOrder: false,
    hidden: false,
    status: null,
    review: true,
    hidden_reason: null,
  });
});
