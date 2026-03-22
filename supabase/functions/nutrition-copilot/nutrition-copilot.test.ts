import test from 'node:test';
import assert from 'node:assert/strict';

import {
  normalizeAnalyzeRequest,
  normalizeCorrectRequest,
  normalizeSuggestRequest,
  mealRecordPayload,
} from './nutrition-copilot.ts';

test('normalizeAnalyzeRequest accepts text-only meal input', () => {
  const normalized = normalizeAnalyzeRequest({
    mode: 'analyze',
    user_id: 'user_123',
    text: 'Chicken salad with avocado',
  });

  assert.equal(normalized.mode, 'analyze');
  assert.equal(normalized.user_id, 'user_123');
  assert.equal(normalized.text, 'Chicken salad with avocado');
  assert.equal(normalized.image_base64, undefined);
});

test('normalizeAnalyzeRequest rejects missing text and image', () => {
  assert.throws(
    () => normalizeAnalyzeRequest({ mode: 'analyze', user_id: 'user_123' }),
    /text or image_base64/i,
  );
});

test('normalizeCorrectRequest requires record id and correction text', () => {
  const normalized = normalizeCorrectRequest({
    mode: 'correct',
    record_id: 'meal_123',
    correction_text: 'It was 2 eggs, not 3',
  });

  assert.equal(normalized.mode, 'correct');
  assert.equal(normalized.record_id, 'meal_123');
  assert.equal(normalized.correction_text, 'It was 2 eggs, not 3');
});

test('normalizeSuggestRequest supports optional context', () => {
  const normalized = normalizeSuggestRequest({
    mode: 'suggest',
    user_id: 'user_123',
    context: 'Going to a steakhouse tonight',
  });

  assert.equal(normalized.mode, 'suggest');
  assert.equal(normalized.context, 'Going to a steakhouse tonight');
});

test('mealRecordPayload produces a records-row payload for analyzed meals', () => {
  const payload = mealRecordPayload({
    userId: 'user_123',
    analysis: {
      meal_name: 'Chicken salad',
      calories: 540,
      protein: 42,
      carbs: 18,
      fat: 28,
      fiber: 7,
      analysis_line: 'High protein, moderate fat, light carbs.',
      confidence: 0.88,
      input_text: 'Chicken salad with avocado',
      photo_url: null,
      meal_time: '2026-03-22T13:00:00Z',
    },
  });

  assert.equal(payload.type, 'measurement');
  assert.equal(payload.category, 'health');
  assert.equal(payload.display_hint, 'meal_log');
  assert.equal(payload.data.meal_name, 'Chicken salad');
  assert.equal(payload.data.corrected, false);
  assert.deepEqual(payload.data.correction_history, []);
});
