import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
  normalizeAnalyzeRequest,
  normalizeCorrectRequest,
  normalizeSuggestRequest,
} from './nutrition-copilot.ts';
import { analyzeMeal, correctMeal, suggestMeals, type RemainingMacros } from './llm.ts';
import { analyzeAndCreateRecord, correctAndLearnRecord } from './nutrition-service.ts';

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
  type: 'meal',
  category: 'nutrition',
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
  const data = await analyzeAndCreateRecord(supabase, request, { analyzeMeal });

  return jsonResponse({ record: data });
}

async function handleCorrect(
  supabase: ReturnType<typeof createServiceClient>,
  input: Record<string, unknown>,
): Promise<Response> {
  const request = normalizeCorrectRequest(input);
  try {
    const updated = await correctAndLearnRecord(supabase, request, { correctMeal });
    return jsonResponse({ record: updated });
  } catch (error) {
    if (error instanceof Error && error.message === 'Meal record not found') {
      throw new HttpError(404, error.message);
    }
    if (error instanceof Error) {
      throw new HttpError(500, error.message);
    }
    throw error;
  }
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
    .eq('category', RECORD_DEFAULTS.category)
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}
