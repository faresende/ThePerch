import type { MealAnalysisResult } from './nutrition-copilot.ts';
import { mealRecordPayload } from './nutrition-copilot.ts';
import {
  buildAnalysisFromFoodMemory,
  buildFoodMemoryRecordMeta,
  buildMemoryPrior,
  learnFoodMemoryFromCorrection,
  lookupFoodMemory,
  recordFoodMemoryMatch,
  resolveFoodMemoryStrategy,
} from './food-memory.ts';

const RECORD_DEFAULTS = {
  agent_id: 'nutrition-copilot',
  type: 'meal',
  category: 'nutrition',
  display_hint: 'meal_log',
} as const;

export interface AnalyzeMealDeps {
  analyzeMeal: (
    text?: string,
    imageBase64?: string,
    options?: { memoryPrior?: Record<string, unknown> | null },
  ) => Promise<MealAnalysisResult>;
}

export interface CorrectMealDeps {
  correctMeal: (original: MealAnalysisResult, correctionText: string) => Promise<MealAnalysisResult>;
}

export async function analyzeAndCreateRecord(
  supabase: ServiceSupabaseClient,
  input: { user_id: string; text?: string; image_base64?: string },
  deps: AnalyzeMealDeps,
): Promise<Record<string, unknown>> {
  const memoryMatch = await lookupFoodMemory(supabase, {
    userId: input.user_id,
    text: input.text,
  });
  const strategy = resolveFoodMemoryStrategy(memoryMatch);

  const analysis = strategy === 'skipped' && memoryMatch
    ? buildAnalysisFromFoodMemory(memoryMatch, {
        inputText: input.text,
        imageProvided: Boolean(input.image_base64),
      })
    : await deps.analyzeMeal(
        input.text,
        input.image_base64,
        strategy === 'prior' && memoryMatch
          ? { memoryPrior: buildMemoryPrior(memoryMatch) }
          : undefined,
      );

  const recordPayload = mealRecordPayload({
    userId: input.user_id,
    analysis,
  });

  recordPayload.data.food_memory = memoryMatch
    ? buildFoodMemoryRecordMeta(memoryMatch, strategy)
    : null;

  const { data, error } = await supabase
    .from('records')
    .insert({
      ...recordPayload,
      ...RECORD_DEFAULTS,
    })
    .select('*')
    .single();

  if (error || !data) {
    throw new Error(`Failed to write meal record: ${error?.message ?? 'unknown error'}`);
  }

  if (memoryMatch && strategy !== 'none') {
    await recordFoodMemoryMatch(supabase, {
      foodMemoryId: memoryMatch.foodMemory.id,
      mealRecordId: String(data.id),
      currentUsageCount: memoryMatch.foodMemory.usage_count,
      confidenceBand: memoryMatch.confidenceBand,
      strategy,
    });
  }

  return data;
}

export async function correctAndLearnRecord(
  supabase: ServiceSupabaseClient,
  input: { record_id: string; correction_text: string; user_id: string },
  deps: CorrectMealDeps,
): Promise<Record<string, unknown>> {
  const { data: existing, error: fetchError } = await supabase
    .from('records')
    .select('*')
    .eq('id', input.record_id)
    .single();

  if (fetchError) {
    if ((fetchError as { code?: string }).code === 'PGRST116') {
      throw new Error('Meal record not found');
    }
    throw new Error(`Failed to load meal record: ${fetchError.message}`);
  }

  // IDOR guard. The supabase client used here is the service-role client,
  // which bypasses RLS — so we MUST verify ownership in code. Without this
  // guard, an authenticated attacker could pass any `record_id` and have
  // the LLM rewrite (and persist) someone else's meal record + corrupt
  // their food_memory entry.
  const ownerId = String(existing?.user_id ?? '');
  if (!ownerId || ownerId !== input.user_id) {
    throw new Error('Meal record not found');
  }

  const original = recordToMealAnalysis(existing ?? {});
  const corrected = await deps.correctMeal(original, input.correction_text);
  const previousHistory = Array.isArray(existing?.data?.correction_history)
    ? existing.data.correction_history
    : [];

  const learnedMemory = await learnFoodMemoryFromCorrection(supabase, {
    userId: ownerId,
    recordId: input.record_id,
    corrected,
    original,
    correctionText: input.correction_text,
    existingFoodMemoryId: readExistingFoodMemoryId(existing),
  });

  const updatedData = {
    ...mealRecordPayload({ userId: ownerId, analysis: corrected }).data,
    corrected: true,
    correction_history: [
      ...previousHistory,
      {
        corrected_at: new Date().toISOString(),
        correction_text: input.correction_text,
        previous: {
          meal_name: original.meal_name,
          calories: original.calories,
          protein: original.protein,
          carbs: original.carbs,
          fat: original.fat,
          fiber: original.fiber ?? null,
          analysis_line: original.analysis_line,
          confidence: original.confidence,
        },
      },
    ],
    food_memory: {
      food_memory_id: learnedMemory.id,
      scope: learnedMemory.scope,
      confidence_band: 'high',
      identity_confidence: Math.max(corrected.confidence, 0.9),
      portion_confidence: 0.9,
      matched_on: 'normalized_name',
      used_as_prior: false,
      llm_strategy: 'none',
    },
  };

  const { data: updated, error: updateError } = await supabase
    .from('records')
    .update({
      title: corrected.meal_name,
      data: updatedData,
    })
    .eq('id', input.record_id)
    .select('*')
    .single();

  if (updateError || !updated) {
    throw new Error(`Failed to update meal record: ${updateError?.message ?? 'unknown error'}`);
  }

  return updated;
}

export function recordToMealAnalysis(record: Record<string, unknown>): MealAnalysisResult {
  const data = isRecord(record.data) ? record.data : {};

  return {
    meal_name: asString(data.meal_name) || asString(record.title) || 'Meal',
    calories: asNumber(data.calories),
    protein: asNumber(data.protein),
    carbs: asNumber(data.carbs),
    fat: asNumber(data.fat),
    fiber: hasValue(data.fiber) ? asNumber(data.fiber) : undefined,
    analysis_line: asString(data.analysis) || 'Meal updated.',
    confidence: asNumber(data.confidence),
    input_text: hasValue(data.input_text) ? asNullableString(data.input_text) : null,
    photo_url: hasValue(data.photo_url) ? asNullableString(data.photo_url) : null,
    meal_time: asString(data.meal_time) || asString(record.created_at) || new Date().toISOString(),
  };
}

function readExistingFoodMemoryId(record: Record<string, unknown> | null): string | null {
  if (!record || !isRecord(record.data) || !isRecord(record.data.food_memory)) {
    return null;
  }

  const value = record.data.food_memory.food_memory_id;
  return typeof value === 'string' && value.trim() ? value : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function hasValue(value: unknown): boolean {
  return value !== null && typeof value !== 'undefined';
}

function asString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function asNullableString(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function asNumber(value: unknown): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }

  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  return 0;
}

type ServiceSupabaseClient = {
  from: (table: string) => QueryBuilder;
};

type QueryBuilder = {
  eq: (column: string, value: unknown) => QueryBuilder;
  select: (columns: string) => QueryBuilder;
  insert: (values: Record<string, unknown>) => QueryBuilder;
  update: (values: Record<string, unknown>) => QueryBuilder;
  single: () => Promise<{ data: Record<string, unknown> | null; error: { message: string; code?: string } | null }>;
};
