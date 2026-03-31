import test from 'node:test';
import assert from 'node:assert/strict';

import {
  normalizeAnalyzeRequest,
  normalizeCorrectRequest,
  normalizeSuggestRequest,
  mealRecordPayload,
} from './nutrition-copilot.ts';
import {
  buildAnalysisFromFoodMemory,
  lookupFoodMemory,
  normalizeFoodText,
  resolveFoodMemoryStrategy,
} from './food-memory.ts';
import { analyzeAndCreateRecord, correctAndLearnRecord } from './nutrition-service.ts';

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

  assert.equal(payload.type, 'meal');
  assert.equal(payload.category, 'nutrition');
  assert.equal(payload.display_hint, 'meal_log');
  assert.equal(payload.data.meal_name, 'Chicken salad');
  assert.equal(payload.data.corrected, false);
  assert.deepEqual(payload.data.correction_history, []);
});

test('normalizeFoodText normalizes user meal text for matching', () => {
  assert.equal(normalizeFoodText('  ON   Shake!! '), 'on shake');
});

test('lookupFoodMemory prefers a high-confidence personal exact match', async () => {
  const supabase = createFoodMemorySupabaseStub({
    personal: [
      {
        id: 'mem_personal',
        user_id: 'user_123',
        scope: 'personal',
        canonical_name: 'ON Shake',
        normalized_name: 'on shake',
        brand: 'ON',
        aliases: ['usual shake'],
        serving_description: '1 bottle',
        serving_basis: 'per_serving',
        calories: 230,
        protein: 48,
        carbs: 6,
        fat: 3,
        fiber: 1,
        portion_notes: null,
        source: 'corrected',
        usage_count: 3,
        last_used_at: '2026-03-28T10:00:00Z',
        confidence_score: 0.92,
        verification_state: 'personal_default',
        reference_meal_record_id: null,
        photo_fingerprint: null,
      },
    ],
    shared: [],
  });

  const match = await lookupFoodMemory(supabase as never, {
    userId: 'user_123',
    text: 'ON shake',
  });

  assert.ok(match);
  assert.equal(match.foodMemory.id, 'mem_personal');
  assert.equal(match.confidenceBand, 'high');
  assert.equal(resolveFoodMemoryStrategy(match), 'prior');
});

test('lookupFoodMemory falls back to shared verified memory when personal memory is absent', async () => {
  const supabase = createFoodMemorySupabaseStub({
    personal: [],
    shared: [
      {
        id: 'mem_shared',
        user_id: null,
        scope: 'shared',
        canonical_name: 'Oatly Barista',
        normalized_name: 'oatly barista',
        brand: 'Oatly',
        aliases: ['oatly milk'],
        serving_description: '240ml serving',
        serving_basis: 'per_serving',
        calories: 120,
        protein: 3,
        carbs: 16,
        fat: 5,
        fiber: 2,
        portion_notes: null,
        source: 'verified_shared',
        usage_count: 10,
        last_used_at: '2026-03-28T10:00:00Z',
        confidence_score: 0.95,
        verification_state: 'shared_verified',
        reference_meal_record_id: null,
        photo_fingerprint: null,
      },
    ],
  });

  const match = await lookupFoodMemory(supabase as never, {
    userId: 'user_123',
    text: 'Oatly Barista',
  });

  assert.ok(match);
  assert.equal(match.foodMemory.scope, 'shared');
  assert.equal(match.confidenceBand, 'high');
});

test('analyzeAndCreateRecord skips the LLM for a high-confidence identity and portion match', async () => {
  let analyzeCalls = 0;
  const supabase = createFullSupabaseStub({
    personal: [
      {
        id: 'mem_personal',
        user_id: 'user_123',
        scope: 'personal',
        canonical_name: 'Overnight Oats',
        normalized_name: 'overnight oats',
        brand: null,
        aliases: ['my usual overnight oats'],
        serving_description: 'my usual jar',
        serving_basis: 'custom',
        calories: 480,
        protein: 32,
        carbs: 48,
        fat: 16,
        fiber: 8,
        portion_notes: 'usual breakfast jar',
        source: 'corrected',
        usage_count: 8,
        last_used_at: '2026-03-28T10:00:00Z',
        confidence_score: 0.96,
        verification_state: 'personal_default',
        reference_meal_record_id: null,
        photo_fingerprint: null,
      },
    ],
    shared: [],
  });

  const record = await analyzeAndCreateRecord(
    supabase as never,
    {
      user_id: 'user_123',
      text: 'my usual overnight oats',
    },
    {
      analyzeMeal: async () => {
        analyzeCalls += 1;
        throw new Error('LLM should not be called');
      },
    },
  );

  assert.equal(analyzeCalls, 0);
  assert.equal(record.title, 'Overnight Oats');
  assert.equal(record.data.food_memory.llm_strategy, 'skipped');
});

test('analyzeAndCreateRecord uses food memory as a prior for medium/high identity with unclear portion', async () => {
  let priorSeen: Record<string, unknown> | null = null;
  const supabase = createFullSupabaseStub({
    personal: [
      {
        id: 'mem_personal',
        user_id: 'user_123',
        scope: 'personal',
        canonical_name: 'ON Shake',
        normalized_name: 'on shake',
        brand: 'ON',
        aliases: ['usual shake'],
        serving_description: '1 bottle',
        serving_basis: 'per_serving',
        calories: 230,
        protein: 48,
        carbs: 6,
        fat: 3,
        fiber: 1,
        portion_notes: null,
        source: 'corrected',
        usage_count: 3,
        last_used_at: '2026-03-28T10:00:00Z',
        confidence_score: 0.92,
        verification_state: 'personal_default',
        reference_meal_record_id: null,
        photo_fingerprint: null,
      },
    ],
    shared: [],
  });

  await analyzeAndCreateRecord(
    supabase as never,
    {
      user_id: 'user_123',
      text: 'ON shake',
    },
    {
      analyzeMeal: async (_text, _imageBase64, options) => {
        priorSeen = options?.memoryPrior ?? null;
        return buildAnalysisFromFoodMemory(
          {
            foodMemory: supabase.__personal[0],
            confidenceBand: 'high',
            identityConfidence: 0.98,
            portionConfidence: 0.45,
            matchedOn: 'normalized_name',
            usedAsPrior: true,
          },
          {
            inputText: 'ON shake',
            imageProvided: false,
          },
        );
      },
    },
  );

  assert.ok(priorSeen);
  assert.equal((priorSeen as { canonical_name: string }).canonical_name, 'ON Shake');
});

test('correctAndLearnRecord updates the meal record and creates a personal food memory', async () => {
  const supabase = createCorrectionSupabaseStub();

  const updated = await correctAndLearnRecord(
    supabase as never,
    {
      record_id: 'record_1',
      correction_text: 'This was the ON shake, 230 kcal and 48g protein.',
    },
    {
      correctMeal: async () => ({
        meal_name: 'ON Shake',
        calories: 230,
        protein: 48,
        carbs: 6,
        fat: 3,
        fiber: 1,
        analysis_line: 'Corrected to your ON shake macros.',
        confidence: 0.96,
        input_text: 'protein shake',
        photo_url: null,
        meal_time: '2026-03-29T09:00:00Z',
      }),
    },
  );

  assert.equal(updated.title, 'ON Shake');
  assert.equal(supabase.__foodMemories.length, 1);
  assert.equal(supabase.__foodMemories[0].canonical_name, 'ON Shake');
  assert.equal(supabase.__observations.at(-1)?.action, 'corrected');
});

function createFoodMemorySupabaseStub(input: {
  personal: Array<Record<string, unknown>>;
  shared: Array<Record<string, unknown>>;
}) {
  return {
    from(table: string) {
      assert.equal(table, 'food_memories');
      return createFoodMemoriesQueryStub(input);
    },
  };
}

function createFullSupabaseStub(input: {
  personal: Array<Record<string, unknown>>;
  shared: Array<Record<string, unknown>>;
}) {
  const records: Array<Record<string, unknown>> = [];
  const observations: Array<Record<string, unknown>> = [];

  const supabase = {
    __personal: input.personal,
    __shared: input.shared,
    __records: records,
    __observations: observations,
    from(table: string) {
      if (table === 'food_memories') {
        return createWritableFoodMemoriesQueryStub(input, observations);
      }
      if (table === 'records') {
        return {
          insert(value: Record<string, unknown>) {
            const inserted = {
              id: `record_${records.length + 1}`,
              ...value,
            };
            records.push(inserted);
            return {
              select() {
                return {
                  async single() {
                    return { data: inserted, error: null };
                  },
                };
              },
            };
          },
        };
      }

      if (table === 'food_memory_observations') {
        return {
          async insert(value: Record<string, unknown>) {
            observations.push(value);
            return { error: null };
          },
        };
      }

      throw new Error(`Unexpected table: ${table}`);
    },
  };

  return supabase;
}

function createCorrectionSupabaseStub() {
  const existingRecord = {
    id: 'record_1',
    user_id: 'user_123',
    title: 'Protein shake',
    data: {
      meal_name: 'Protein shake',
      calories: 300,
      protein: 30,
      carbs: 18,
      fat: 7,
      fiber: 2,
      analysis: 'Estimated shake.',
      photo_url: null,
      corrected: false,
      correction_history: [],
      input_text: 'protein shake',
      meal_time: '2026-03-29T09:00:00Z',
      confidence: 0.6,
    },
  };

  const foodMemories: Array<Record<string, unknown>> = [];
  const observations: Array<Record<string, unknown>> = [];

  return {
    __foodMemories: foodMemories,
    __observations: observations,
    from(table: string) {
      if (table === 'records') {
        return {
          select() {
            return this;
          },
          eq() {
            return this;
          },
          async single() {
            return { data: existingRecord, error: null };
          },
          update(value: Record<string, unknown>) {
            const updated = {
              ...existingRecord,
              ...value,
            };
            return {
              eq() {
                return this;
              },
              select() {
                return {
                  async single() {
                    return { data: updated, error: null };
                  },
                };
              },
            };
          },
        };
      }

      if (table === 'food_memories') {
        return {
          select() {
            return this;
          },
          eq(column: string, value: unknown) {
            if (column === 'id') {
              this.__selected = foodMemories.find((item) => item.id === value) ?? null;
            }
            if (column === 'user_id') {
              this.__selected = foodMemories.find((item) => item.user_id === value) ?? null;
            }
            if (column === 'normalized_name') {
              this.__selected = foodMemories.find((item) => item.normalized_name === value) ?? null;
            }
            return this;
          },
          async maybeSingle() {
            return { data: this.__selected ?? null, error: null };
          },
          insert(value: Record<string, unknown>) {
            const inserted = {
              id: `mem_${foodMemories.length + 1}`,
              ...value,
            };
            foodMemories.push(inserted);
            return {
              select() {
                return {
                  async single() {
                    return { data: inserted, error: null };
                  },
                };
              },
            };
          },
          update(value: Record<string, unknown>) {
            const current = this.__selected ?? foodMemories[0];
            const updated = {
              ...current,
              ...value,
            };
            if (current) {
              const index = foodMemories.findIndex((item) => item.id === current.id);
              foodMemories[index] = updated;
            }
            return {
              eq() {
                return this;
              },
              select() {
                return {
                  async single() {
                    return { data: updated, error: null };
                  },
                };
              },
            };
          },
        };
      }

      if (table === 'food_memory_observations') {
        return {
          async insert(value: Record<string, unknown>) {
            observations.push(value);
            return { error: null };
          },
        };
      }

      throw new Error(`Unexpected table: ${table}`);
    },
  };
}

function createFoodMemoriesQueryStub(input: {
  personal: Array<Record<string, unknown>>;
  shared: Array<Record<string, unknown>>;
}) {
  return createBaseFoodMemoryQuery(input, null);
}

function createWritableFoodMemoriesQueryStub(
  input: {
    personal: Array<Record<string, unknown>>;
    shared: Array<Record<string, unknown>>;
  },
  observations: Array<Record<string, unknown>>,
) {
  const base = createBaseFoodMemoryQuery(input, observations);
  return {
    ...base,
    update(value: Record<string, unknown>) {
      return {
        eq(column: string, id: unknown) {
          const pool = [...input.personal, ...input.shared];
          const target = pool.find((item) => item[column] === id);
          if (target) {
            Object.assign(target, value);
          }
          return {
            async then(resolve: (value: unknown) => unknown) {
              return resolve({ data: null, error: null });
            },
          };
        },
      };
    },
  };
}

function createBaseFoodMemoryQuery(
  input: {
    personal: Array<Record<string, unknown>>;
    shared: Array<Record<string, unknown>>;
  },
  _observations: Array<Record<string, unknown>> | null,
) {
  const state = {
    scope: 'personal',
    userId: null as string | null,
    normalizedName: null as string | null,
    verificationState: null as string | null,
    limitValue: 50,
  };

  const query = {
    select() {
      return this;
    },
    eq(column: string, value: unknown) {
      if (column === 'scope') state.scope = String(value);
      if (column === 'user_id') state.userId = String(value);
      if (column === 'normalized_name') state.normalizedName = String(value);
      if (column === 'verification_state') state.verificationState = String(value);
      return this;
    },
    order() {
      return this;
    },
    limit(value: number) {
      state.limitValue = value;
      return this;
    },
    async then(resolve: (value: { data: Array<Record<string, unknown>>; error: null }) => unknown) {
      const source = state.scope === 'shared' ? input.shared : input.personal;
      const rows = source
        .filter((row) => !state.userId || row.user_id === state.userId)
        .filter((row) => !state.verificationState || row.verification_state === state.verificationState)
        .filter((row) => !state.normalizedName || row.normalized_name === state.normalizedName)
        .slice(0, state.limitValue);

      return resolve({ data: rows, error: null });
    },
  };

  return query;
}
