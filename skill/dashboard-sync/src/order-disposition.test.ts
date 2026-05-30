import test from 'node:test';
import assert from 'node:assert/strict';

import { dispositionForClassification } from './order-disposition';
import { classifyForTracking, type ClassifyResult } from './classification-cascade';
import type { LLMExtractedFields } from './llm-extractor';

// Mirror the adapter closures handlePurchaseConfirmation builds around
// classifyForTracking, so these tests lock in the end-to-end decision
// (cascade verdict → disposition) for an injected rule + LLM object
// without touching the DB. `lookupRule` returns rule?.action ?? null and
// `llm` reuses the already-fetched extractor object's classification +
// confidence — exactly how the live wiring composes them.
function runPipeline(opts: {
  ruleAction?: string | null;
  llm?: Partial<LLMExtractedFields> | null;
  senderEmail?: string;
}) {
  return classifyForTracking(
    { subject: 's', body: 'b', senderEmail: opts.senderEmail ?? 'shop@example-merchant.com', senderName: 'Shop' },
    {
      lookupRule: async () => opts.ruleAction ?? null,
      llm: async () => ({
        classification: opts.llm?.classification ?? 'unsure',
        confidence: opts.llm?.confidence ?? 0,
      }),
    },
  );
}

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

// ─── Wiring: cascade(injected deps) → disposition ─────────────────────

test('wiring: a learned always_digital rule yields a hidden digital order', async () => {
  const result = await runPipeline({ ruleAction: 'always_digital' });
  const disp = dispositionForClassification(result);
  assert.equal(result.classification, 'digital');
  assert.equal(result.reason, 'learned-rule');
  assert.equal(disp.createOrder, true);
  assert.equal(disp.hidden, true);
  assert.equal(disp.status, 'digital');
  assert.equal(disp.hidden_reason, 'learned-rule');
});

test('wiring: a high-confidence physical LLM verdict yields a surfaced order', async () => {
  const result = await runPipeline({ llm: { classification: 'physical', confidence: 0.9 } });
  const disp = dispositionForClassification(result);
  assert.equal(result.classification, 'physical');
  assert.equal(disp.createOrder, true);
  assert.equal(disp.hidden, false);
  assert.equal(disp.status, 'ordered');
});

test('wiring: a mid-band LLM verdict routes to review (no order)', async () => {
  const result = await runPipeline({ llm: { classification: 'physical', confidence: 0.6 } });
  const disp = dispositionForClassification(result);
  assert.equal(result.classification, 'unsure');
  assert.equal(disp.createOrder, false);
  assert.equal(disp.review, true);
});

test('wiring: a missing LLM object (unsure@0) routes to review', async () => {
  // Reproduces the `llm?.classification ?? 'unsure', llm?.confidence ?? 0`
  // degradation path when the extractor returned null.
  const result = await runPipeline({ llm: null });
  const disp = dispositionForClassification(result);
  assert.equal(result.classification, 'unsure');
  assert.equal(disp.review, true);
});
