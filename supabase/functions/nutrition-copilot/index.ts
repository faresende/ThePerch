import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
  mealRecordPayload,
  normalizeAnalyzeRequest,
  normalizeCorrectRequest,
  normalizeSuggestRequest,
  type MealAnalysisResult,
} from './nutrition-copilot.ts';
import { analyzeMeal, correctMeal, suggestMeals, type RemainingMacros } from './llm.ts';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
};

const DAILY_TARGETS = {
  calories: 2200,
  protein: 180,
  carbs: 250,
  fat: 70,
  fiber: 30,
};

const RECORD_DEFAULTS = {
  agent_id: 'nutrition-copilot',
  type: 'meal',
  category: 'nutrition',
  display_hint: 'meal_log',
} as const;

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    const body = await req.json();
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      throw new HttpError(400, 'Request body must be a JSON object');
    }

    const supabase = createServiceClient();
    const mode = typeof body.mode === 'string' ? body.mode : '';

    switch (mode) {
      case 'analyze':
        return await handleAnalyze(supabase, body as Record<string, unknown>);
      case 'correct':
        return await handleCorrect(supabase, body as Record<string, unknown>);
      case 'suggest':
        return await handleSuggest(supabase, body as Record<string, unknown>);
      default:
        throw new HttpError(400, 'mode must be one of: analyze, correct, suggest');
    }
  } catch (error) {
    return handleError(error);
  }
});

async function handleAnalyze(
  supabase: ReturnType<typeof createServiceClient>,
  input: Record<string, unknown>,
): Promise<Response> {
  const request = normalizeAnalyzeRequest(input);
  const analysis = await analyzeMeal(request.text, request.image_base64);

  const insertPayload = {
    ...mealRecordPayload({ userId: request.user_id, analysis }),
    ...RECORD_DEFAULTS,
  };

  const { data, error } = await supabase
    .from('records')
    .insert(insertPayload)
    .select('*')
    .single();

  if (error) {
    throw new HttpError(500, `Failed to write meal record: ${error.message}`);
  }

  return jsonResponse({ record: data });
}

async function handleCorrect(
  supabase: ReturnType<typeof createServiceClient>,
  input: Record<string, unknown>,
): Promise<Response> {
  const request = normalizeCorrectRequest(input);

  const { data: existing, error: fetchError } = await supabase
    .from('records')
    .select('*')
    .eq('id', request.record_id)
    .single();

  if (fetchError) {
    if (fetchError.code === 'PGRST116') {
      throw new HttpError(404, 'Meal record not found');
    }
    throw new HttpError(500, `Failed to load meal record: ${fetchError.message}`);
  }

  const original = recordToMealAnalysis(existing);
  const corrected = await correctMeal(original, request.correction_text);
  const previousHistory = Array.isArray(existing.data?.correction_history)
    ? existing.data.correction_history
    : [];

  const updatedData = {
    ...mealRecordPayload({ userId: existing.user_id, analysis: corrected }).data,
    corrected: true,
    correction_history: [
      ...previousHistory,
      {
        corrected_at: new Date().toISOString(),
        correction_text: request.correction_text,
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
  };

  const { data: updated, error: updateError } = await supabase
    .from('records')
    .update({
      title: corrected.meal_name,
      data: updatedData,
    })
    .eq('id', request.record_id)
    .select('*')
    .single();

  if (updateError) {
    throw new HttpError(500, `Failed to update meal record: ${updateError.message}`);
  }

  return jsonResponse({ record: updated });
}

async function handleSuggest(
  supabase: ReturnType<typeof createServiceClient>,
  input: Record<string, unknown>,
): Promise<Response> {
  const request = normalizeSuggestRequest(input);
  const { start, end, contextDate } = getUtcDayRange(new Date());

  const { data: meals, error } = await supabase
    .from('records')
    .select('id, title, data, created_at')
    .eq('user_id', request.user_id)
    .eq('agent_id', RECORD_DEFAULTS.agent_id)
    .eq('type', RECORD_DEFAULTS.type)
    .gte('created_at', start)
    .lt('created_at', end)
    .order('created_at', { ascending: true });

  if (error) {
    throw new HttpError(500, `Failed to load today’s meals: ${error.message}`);
  }

  const consumed = sumConsumedMacros(meals ?? []);
  const remaining: RemainingMacros = {
    calories: Math.max(0, DAILY_TARGETS.calories - consumed.calories),
    protein: Math.max(0, DAILY_TARGETS.protein - consumed.protein),
    carbs: Math.max(0, DAILY_TARGETS.carbs - consumed.carbs),
    fat: Math.max(0, DAILY_TARGETS.fat - consumed.fat),
    fiber: Math.max(0, DAILY_TARGETS.fiber - consumed.fiber),
  };

  const suggestions = await suggestMeals(remaining, request.context);

  return jsonResponse({
    date: contextDate,
    targets: DAILY_TARGETS,
    consumed,
    remaining,
    suggestions,
  });
}

function createServiceClient() {
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  if (!supabaseUrl) {
    throw new Error('SUPABASE_URL is not configured');
  }

  if (!serviceRoleKey) {
    throw new Error('SUPABASE_SERVICE_ROLE_KEY is not configured');
  }

  return createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });
}

function recordToMealAnalysis(record: Record<string, unknown>): MealAnalysisResult {
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

function sumConsumedMacros(records: Array<Record<string, unknown>>) {
  return records.reduce(
    (totals, record) => {
      const data = isRecord(record.data) ? record.data : {};

      totals.calories += asNumber(data.calories);
      totals.protein += asNumber(data.protein);
      totals.carbs += asNumber(data.carbs);
      totals.fat += asNumber(data.fat);
      totals.fiber += asNumber(data.fiber);

      return totals;
    },
    { calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0 },
  );
}

function getUtcDayRange(date: Date) {
  const startDate = new Date(Date.UTC(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate(),
    0,
    0,
    0,
    0,
  ));
  const endDate = new Date(startDate);
  endDate.setUTCDate(endDate.getUTCDate() + 1);

  return {
    start: startDate.toISOString(),
    end: endDate.toISOString(),
    contextDate: startDate.toISOString().slice(0, 10),
  };
}

function handleError(error: unknown): Response {
  if (error instanceof HttpError) {
    return jsonResponse({ error: error.message }, error.status);
  }

  if (error instanceof SyntaxError) {
    return jsonResponse({ error: 'Invalid JSON body' }, 400);
  }

  const message = error instanceof Error ? error.message : 'Internal server error';
  return jsonResponse({ error: message }, 500);
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: CORS_HEADERS,
  });
}

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
    this.name = 'HttpError';
  }
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
