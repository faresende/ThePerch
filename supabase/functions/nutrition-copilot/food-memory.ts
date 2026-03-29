import type { MealAnalysisResult } from './nutrition-copilot.ts';

export type FoodMemoryScope = 'personal' | 'shared';
export type FoodMemoryConfidenceBand = 'high' | 'medium' | 'low';
export type FoodMemoryObservationAction =
  | 'created_from_analysis'
  | 'matched'
  | 'corrected'
  | 'promoted_to_shared'
  | 'demoted';

export interface FoodMemoryRow {
  id: string;
  user_id: string | null;
  scope: FoodMemoryScope;
  canonical_name: string;
  normalized_name: string;
  brand: string | null;
  aliases: string[];
  serving_description: string | null;
  serving_basis: 'per_item' | 'per_100g' | 'per_serving' | 'custom';
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber: number;
  portion_notes: string | null;
  source: 'manual' | 'llm' | 'corrected' | 'verified_shared';
  usage_count: number;
  last_used_at: string | null;
  confidence_score: number;
  verification_state: 'personal_default' | 'shared_candidate' | 'shared_verified' | 'rejected';
  reference_meal_record_id: string | null;
  photo_fingerprint: string | null;
  created_at?: string;
  updated_at?: string;
}

export interface FoodMemoryMatch {
  foodMemory: FoodMemoryRow;
  confidenceBand: FoodMemoryConfidenceBand;
  identityConfidence: number;
  portionConfidence: number;
  matchedOn: 'normalized_name' | 'alias' | 'brand' | 'fuzzy';
  usedAsPrior: boolean;
}

export interface FoodMemoryPrior {
  food_memory_id: string;
  canonical_name: string;
  brand: string | null;
  serving_description: string | null;
  portion_notes: string | null;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber: number;
  identity_confidence: number;
  portion_confidence: number;
  matched_on: FoodMemoryMatch['matchedOn'];
}

export interface FoodMemoryRecordMeta {
  food_memory_id: string;
  scope: FoodMemoryScope;
  confidence_band: FoodMemoryConfidenceBand;
  identity_confidence: number;
  portion_confidence: number;
  matched_on: FoodMemoryMatch['matchedOn'];
  used_as_prior: boolean;
  llm_strategy: 'skipped' | 'prior' | 'none';
}

const HIGH_CONFIDENCE_THRESHOLD = 0.9;
const MEDIUM_CONFIDENCE_THRESHOLD = 0.72;
const HIGH_PORTION_THRESHOLD = 0.74;

const PORTION_HINT_PATTERN =
  /\b(\d+(?:\.\d+)?\s?(?:g|gram|grams|kg|oz|ml|cup|cups|tbsp|tablespoon|tsp|teaspoon|slice|slices|piece|pieces|serving|servings|scoop|scoops|egg|eggs|bowl|bowls|plate|plates|pack|packs|packet|packets|bar|bars))\b/i;

const USUAL_HINT_PATTERN = /\b(my usual|usual|same as always|the usual|regular order)\b/i;

export async function lookupFoodMemory(
  supabase: FoodMemorySupabaseClient,
  input: { userId: string; text?: string; mealName?: string },
): Promise<FoodMemoryMatch | null> {
  const candidates = buildLookupCandidates(input.text, input.mealName);
  if (candidates.length === 0) {
    return null;
  }

  const seen = new Set<string>();
  const personalRows = await fetchFoodMemories(supabase, {
    scope: 'personal',
    userId: input.userId,
    normalizedName: candidates[0],
  });
  const sharedRows = await fetchFoodMemories(supabase, {
    scope: 'shared',
    normalizedName: candidates[0],
  });

  const pool = [...personalRows, ...sharedRows].filter((row) => {
    if (seen.has(row.id)) return false;
    seen.add(row.id);
    return true;
  });

  if (pool.length === 0) {
    return null;
  }

  let best: FoodMemoryMatch | null = null;
  for (const row of pool) {
    const match = scoreFoodMemory(row, candidates, input.text);
    if (!match) continue;
    if (!best || compareMatches(match, best) > 0) {
      best = match;
    }
  }

  return best;
}

export function buildAnalysisFromFoodMemory(
  match: FoodMemoryMatch,
  context: { inputText?: string; imageProvided: boolean; mealTime?: string },
): MealAnalysisResult {
  const memory = match.foodMemory;
  const summaryPrefix = memory.brand ? `${memory.brand} ${memory.canonical_name}` : memory.canonical_name;
  const servingHint = memory.serving_description || memory.portion_notes || 'your usual serving';

  return {
    meal_name: memory.canonical_name,
    calories: roundMacro(memory.calories),
    protein: roundMacro(memory.protein),
    carbs: roundMacro(memory.carbs),
    fat: roundMacro(memory.fat),
    fiber: roundMacro(memory.fiber),
    analysis_line: `Used your saved ${summaryPrefix} memory for ${servingHint}.`,
    confidence: clamp((match.identityConfidence * 0.75) + (match.portionConfidence * 0.25), 0, 1),
    input_text: context.inputText ?? null,
    photo_url: null,
    meal_time: context.mealTime ?? new Date().toISOString(),
  };
}

export function buildMemoryPrior(match: FoodMemoryMatch): FoodMemoryPrior {
  return {
    food_memory_id: match.foodMemory.id,
    canonical_name: match.foodMemory.canonical_name,
    brand: match.foodMemory.brand,
    serving_description: match.foodMemory.serving_description,
    portion_notes: match.foodMemory.portion_notes,
    calories: roundMacro(match.foodMemory.calories),
    protein: roundMacro(match.foodMemory.protein),
    carbs: roundMacro(match.foodMemory.carbs),
    fat: roundMacro(match.foodMemory.fat),
    fiber: roundMacro(match.foodMemory.fiber),
    identity_confidence: match.identityConfidence,
    portion_confidence: match.portionConfidence,
    matched_on: match.matchedOn,
  };
}

export function buildFoodMemoryRecordMeta(
  match: FoodMemoryMatch,
  strategy: 'skipped' | 'prior' | 'none',
): FoodMemoryRecordMeta {
  return {
    food_memory_id: match.foodMemory.id,
    scope: match.foodMemory.scope,
    confidence_band: match.confidenceBand,
    identity_confidence: match.identityConfidence,
    portion_confidence: match.portionConfidence,
    matched_on: match.matchedOn,
    used_as_prior: strategy === 'prior',
    llm_strategy: strategy,
  };
}

export async function recordFoodMemoryMatch(
  supabase: FoodMemorySupabaseClient,
  input: {
    foodMemoryId: string;
    mealRecordId: string;
    currentUsageCount: number;
    confidenceBand: FoodMemoryConfidenceBand;
    strategy: 'skipped' | 'prior';
  },
): Promise<void> {
  const { error: updateError } = await supabase
    .from('food_memories')
    .update({
      usage_count: input.currentUsageCount + 1,
      last_used_at: new Date().toISOString(),
    })
    .eq('id', input.foodMemoryId);

  if (updateError) {
    throw new Error(`Failed to update food memory usage: ${updateError.message}`);
  }

  await insertObservation(supabase, {
    food_memory_id: input.foodMemoryId,
    meal_record_id: input.mealRecordId,
    action: 'matched',
    notes: `band=${input.confidenceBand};strategy=${input.strategy}`,
  });
}

export async function learnFoodMemoryFromCorrection(
  supabase: FoodMemorySupabaseClient,
  input: {
    userId: string;
    recordId: string;
    corrected: MealAnalysisResult;
    original: MealAnalysisResult;
    correctionText: string;
    existingFoodMemoryId?: string | null;
  },
): Promise<FoodMemoryRow> {
  const normalizedName = normalizeFoodText(input.corrected.meal_name);
  if (!normalizedName) {
    throw new Error('Cannot learn food memory without a meal name');
  }

  const aliases = buildAliases([
    input.original.input_text,
    input.original.meal_name,
    input.corrected.meal_name,
  ]);

  const brand = inferBrand(input.original.input_text) || inferBrand(input.corrected.meal_name);
  const existing = input.existingFoodMemoryId
    ? await fetchFoodMemoryById(supabase, input.existingFoodMemoryId)
    : await fetchExistingPersonalFoodMemory(supabase, input.userId, normalizedName);

  const payload = {
    user_id: input.userId,
    scope: 'personal',
    canonical_name: input.corrected.meal_name,
    normalized_name: normalizedName,
    brand: brand ?? existing?.brand ?? null,
    aliases: mergeAliases(existing?.aliases ?? [], aliases),
    serving_description: existing?.serving_description ?? input.original.input_text ?? input.corrected.meal_name,
    serving_basis: existing?.serving_basis ?? 'custom',
    calories: roundMacro(input.corrected.calories),
    protein: roundMacro(input.corrected.protein),
    carbs: roundMacro(input.corrected.carbs),
    fat: roundMacro(input.corrected.fat),
    fiber: roundMacro(input.corrected.fiber ?? 0),
    portion_notes: input.correctionText,
    source: 'corrected',
    usage_count: (existing?.usage_count ?? 0) + 1,
    last_used_at: new Date().toISOString(),
    confidence_score: clamp(Math.max(existing?.confidence_score ?? 0, input.corrected.confidence, 0.85), 0, 1),
    verification_state: existing?.verification_state ?? 'personal_default',
    reference_meal_record_id: input.recordId,
    photo_fingerprint: existing?.photo_fingerprint ?? null,
  } as const;

  const response = existing
    ? await supabase
        .from('food_memories')
        .update(payload)
        .eq('id', existing.id)
        .select('*')
        .single()
    : await supabase
        .from('food_memories')
        .insert(payload)
        .select('*')
        .single();

  if (response.error || !response.data) {
    throw new Error(`Failed to persist corrected food memory: ${response.error?.message ?? 'unknown error'}`);
  }

  await insertObservation(supabase, {
    food_memory_id: response.data.id,
    meal_record_id: input.recordId,
    action: 'corrected',
    notes: input.correctionText,
  });

  return mapFoodMemoryRow(response.data);
}

export function resolveFoodMemoryStrategy(match: FoodMemoryMatch | null): 'skipped' | 'prior' | 'none' {
  if (!match) return 'none';
  if (match.confidenceBand === 'high' && match.portionConfidence >= HIGH_PORTION_THRESHOLD) {
    return 'skipped';
  }
  if (match.confidenceBand === 'high' || match.confidenceBand === 'medium') {
    return 'prior';
  }
  return 'none';
}

export function normalizeFoodText(value: string | null | undefined): string {
  if (!value) return '';

  return value
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function buildLookupCandidates(text?: string, mealName?: string): string[] {
  return [...new Set([text, mealName].map((value) => normalizeFoodText(value)).filter(Boolean))];
}

async function fetchFoodMemories(
  supabase: FoodMemorySupabaseClient,
  input: { scope: FoodMemoryScope; userId?: string; normalizedName: string },
): Promise<FoodMemoryRow[]> {
  const baseQuery = () => {
    let query = supabase
      .from('food_memories')
      .select('*')
      .eq('scope', input.scope)
      .order('usage_count', { ascending: false })
      .order('last_used_at', { ascending: false, nullsFirst: false })
      .limit(50);

    if (input.scope === 'personal' && input.userId) {
      query = query.eq('user_id', input.userId);
    }

    if (input.scope === 'shared') {
      query = query.eq('verification_state', 'shared_verified');
    }

    return query;
  };

  const exact = await baseQuery().eq('normalized_name', input.normalizedName);
  if (exact.error) {
    throw new Error(`Failed to load food memories: ${exact.error.message}`);
  }

  const exactRows = (exact.data ?? []).map(mapFoodMemoryRow);
  if (exactRows.length > 0) {
    return exactRows;
  }

  const fallback = await baseQuery();
  if (fallback.error) {
    throw new Error(`Failed to load food memories: ${fallback.error.message}`);
  }

  return (fallback.data ?? []).map(mapFoodMemoryRow);
}

async function fetchExistingPersonalFoodMemory(
  supabase: FoodMemorySupabaseClient,
  userId: string,
  normalizedName: string,
): Promise<FoodMemoryRow | null> {
  const { data, error } = await supabase
    .from('food_memories')
    .select('*')
    .eq('user_id', userId)
    .eq('scope', 'personal')
    .eq('normalized_name', normalizedName)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to load existing personal food memory: ${error.message}`);
  }

  return data ? mapFoodMemoryRow(data) : null;
}

async function fetchFoodMemoryById(
  supabase: FoodMemorySupabaseClient,
  id: string,
): Promise<FoodMemoryRow | null> {
  const { data, error } = await supabase
    .from('food_memories')
    .select('*')
    .eq('id', id)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to load food memory: ${error.message}`);
  }

  return data ? mapFoodMemoryRow(data) : null;
}

async function insertObservation(
  supabase: FoodMemorySupabaseClient,
  payload: {
    food_memory_id: string;
    meal_record_id: string;
    action: FoodMemoryObservationAction;
    notes?: string;
  },
): Promise<void> {
  const { error } = await supabase.from('food_memory_observations').insert(payload);
  if (error) {
    throw new Error(`Failed to write food memory observation: ${error.message}`);
  }
}

function scoreFoodMemory(
  row: FoodMemoryRow,
  candidates: string[],
  rawText?: string,
): FoodMemoryMatch | null {
  let best: Omit<FoodMemoryMatch, 'foodMemory' | 'usedAsPrior'> | null = null;

  for (const candidate of candidates) {
    const aliasSet = new Set([row.normalized_name, ...row.aliases.map((alias) => normalizeFoodText(alias))]);
    const brandCandidate = normalizeFoodText([row.brand, row.canonical_name].filter(Boolean).join(' '));
    let identity = 0;
    let matchedOn: FoodMemoryMatch['matchedOn'] = 'fuzzy';

    if (candidate === row.normalized_name) {
      identity = row.scope === 'personal' ? 0.98 : 0.95;
      matchedOn = 'normalized_name';
    } else if (aliasSet.has(candidate)) {
      identity = row.scope === 'personal' ? 0.96 : 0.92;
      matchedOn = 'alias';
    } else if (brandCandidate && candidate.includes(brandCandidate)) {
      identity = row.scope === 'personal' ? 0.9 : 0.84;
      matchedOn = 'brand';
    } else {
      const overlap = tokenOverlap(candidate, row.normalized_name);
      if (overlap >= 0.5) {
        identity = overlap * (row.scope === 'personal' ? 0.96 : 0.88);
      }
    }

    identity = clamp(Math.max(identity, row.confidence_score * 0.15), 0, 1);
    const confidenceBand = identity >= HIGH_CONFIDENCE_THRESHOLD
      ? 'high'
      : identity >= MEDIUM_CONFIDENCE_THRESHOLD
      ? 'medium'
      : 'low';

    const portionConfidence = estimatePortionConfidence(rawText, row);
    const candidateMatch = {
      confidenceBand,
      identityConfidence: identity,
      portionConfidence,
      matchedOn,
    } satisfies Omit<FoodMemoryMatch, 'foodMemory' | 'usedAsPrior'>;

    if (!best || compareScoredMatches(candidateMatch, best) > 0) {
      best = candidateMatch;
    }
  }

  if (!best) return null;

  return {
    foodMemory: row,
    ...best,
    usedAsPrior: false,
  };
}

function compareMatches(left: FoodMemoryMatch, right: FoodMemoryMatch): number {
  return compareScoredMatches(left, right)
    || left.foodMemory.scope.localeCompare(right.foodMemory.scope) * -1
    || left.foodMemory.usage_count - right.foodMemory.usage_count;
}

function compareScoredMatches(
  left: Pick<FoodMemoryMatch, 'confidenceBand' | 'identityConfidence' | 'portionConfidence'>,
  right: Pick<FoodMemoryMatch, 'confidenceBand' | 'identityConfidence' | 'portionConfidence'>,
): number {
  return bandWeight(left.confidenceBand) - bandWeight(right.confidenceBand)
    || left.identityConfidence - right.identityConfidence
    || left.portionConfidence - right.portionConfidence;
}

function bandWeight(band: FoodMemoryConfidenceBand): number {
  if (band === 'high') return 3;
  if (band === 'medium') return 2;
  return 1;
}

function estimatePortionConfidence(rawText: string | undefined, row: FoodMemoryRow): number {
  const text = rawText?.trim();
  if (!text) {
    return row.serving_description ? 0.3 : 0.15;
  }
  if (USUAL_HINT_PATTERN.test(text)) {
    return 0.95;
  }
  if (PORTION_HINT_PATTERN.test(text)) {
    return 0.82;
  }
  if (row.serving_description && normalizeFoodText(text).includes(normalizeFoodText(row.serving_description))) {
    return 0.7;
  }
  return 0.45;
}

function tokenOverlap(left: string, right: string): number {
  const leftTokens = new Set(left.split(' ').filter(Boolean));
  const rightTokens = new Set(right.split(' ').filter(Boolean));
  if (leftTokens.size === 0 || rightTokens.size === 0) return 0;

  let matches = 0;
  for (const token of leftTokens) {
    if (rightTokens.has(token)) matches += 1;
  }

  return matches / Math.max(leftTokens.size, rightTokens.size);
}

function buildAliases(values: Array<string | null | undefined>): string[] {
  return [...new Set(values.map((value) => normalizeFoodText(value)).filter(Boolean))];
}

function mergeAliases(existing: string[], next: string[]): string[] {
  return [...new Set([...existing.map((value) => normalizeFoodText(value)), ...next])]
    .filter(Boolean)
    .slice(0, 12);
}

function inferBrand(value?: string | null): string | null {
  if (!value) return null;

  const raw = value.trim();
  const firstToken = raw.split(/\s+/)[0] ?? '';
  if (/^[A-Z0-9]{2,8}$/.test(firstToken)) {
    return firstToken;
  }

  const titlePrefix = raw.match(/^([A-Z][a-zA-Z0-9&'-]{1,20})\b/);
  return titlePrefix ? titlePrefix[1] : null;
}

function mapFoodMemoryRow(row: Record<string, unknown>): FoodMemoryRow {
  return {
    id: String(row.id),
    user_id: asNullableString(row.user_id),
    scope: row.scope === 'shared' ? 'shared' : 'personal',
    canonical_name: asString(row.canonical_name),
    normalized_name: asString(row.normalized_name),
    brand: asNullableString(row.brand),
    aliases: Array.isArray(row.aliases) ? row.aliases.map((alias) => asString(alias)).filter(Boolean) : [],
    serving_description: asNullableString(row.serving_description),
    serving_basis: normalizeServingBasis(row.serving_basis),
    calories: asNumber(row.calories),
    protein: asNumber(row.protein),
    carbs: asNumber(row.carbs),
    fat: asNumber(row.fat),
    fiber: asNumber(row.fiber),
    portion_notes: asNullableString(row.portion_notes),
    source: normalizeSource(row.source),
    usage_count: asNumber(row.usage_count),
    last_used_at: asNullableString(row.last_used_at),
    confidence_score: clamp(asNumber(row.confidence_score), 0, 1),
    verification_state: normalizeVerificationState(row.verification_state),
    reference_meal_record_id: asNullableString(row.reference_meal_record_id),
    photo_fingerprint: asNullableString(row.photo_fingerprint),
    created_at: asNullableString(row.created_at) ?? undefined,
    updated_at: asNullableString(row.updated_at) ?? undefined,
  };
}

function normalizeServingBasis(value: unknown): FoodMemoryRow['serving_basis'] {
  if (value === 'per_item' || value === 'per_100g' || value === 'per_serving') {
    return value;
  }
  return 'custom';
}

function normalizeSource(value: unknown): FoodMemoryRow['source'] {
  if (value === 'llm' || value === 'corrected' || value === 'verified_shared') {
    return value;
  }
  return 'manual';
}

function normalizeVerificationState(value: unknown): FoodMemoryRow['verification_state'] {
  if (value === 'shared_candidate' || value === 'shared_verified' || value === 'rejected') {
    return value;
  }
  return 'personal_default';
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
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }

  return 0;
}

function roundMacro(value: number): number {
  return Math.round(value * 100) / 100;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

type FoodMemorySupabaseClient = {
  from: (table: string) => FoodMemoryTableClient;
};

type QueryBuilder = {
  eq: (column: string, value: unknown) => QueryBuilder;
  order: (column: string, options?: Record<string, unknown>) => QueryBuilder;
  limit: (value: number) => QueryBuilder;
  maybeSingle: () => Promise<{ data: Record<string, unknown> | null; error: { message: string } | null }>;
  single: () => Promise<{ data: Record<string, unknown> | null; error: { message: string } | null }>;
  select: (columns: string) => QueryBuilder;
  then?: (
    resolve: (value: { data: Array<Record<string, unknown>> | null; error: { message: string } | null }) => unknown,
    reject?: (reason: unknown) => unknown,
  ) => unknown;
};

type FoodMemoryTableClient = QueryBuilder & {
  update: (values: Record<string, unknown>) => QueryBuilder;
  insert: (values: Record<string, unknown> | Array<Record<string, unknown>>) => QueryBuilder;
};
