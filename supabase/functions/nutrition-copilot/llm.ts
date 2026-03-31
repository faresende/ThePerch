import type { MealAnalysisResult } from './nutrition-copilot.ts';

const ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_MODEL = 'claude-sonnet-4-20250514';

const ANALYZE_SYSTEM_PROMPT = `
You are Nutrition Copilot for a health tracking app.

Estimate nutrition from a meal description or photo. Be decisive, practical, and concise.
Return JSON only with this exact shape:
{
  "meal_name": string,
  "calories": number,
  "protein": number,
  "carbs": number,
  "fat": number,
  "fiber": number,
  "analysis_line": string,
  "confidence": number
}

Rules:
- Estimate realistic macros for the meal as consumed.
- Use grams for protein, carbs, fat, and fiber.
- confidence must be between 0 and 1.
- analysis_line must be one opinionated sentence, not a paragraph.
- Never wrap the JSON in markdown.
`.trim();

const CORRECT_SYSTEM_PROMPT = `
You update an existing structured meal nutrition estimate after the user provides a correction.

Return JSON only with this exact shape:
{
  "meal_name": string,
  "calories": number,
  "protein": number,
  "carbs": number,
  "fat": number,
  "fiber": number,
  "analysis_line": string,
  "confidence": number
}

Rules:
- Start from the original meal analysis and revise it to reflect the user's correction.
- Keep values realistic and internally consistent.
- confidence must be between 0 and 1.
- analysis_line must stay as one sentence.
- Never wrap the JSON in markdown.
`.trim();

const SUGGEST_SYSTEM_PROMPT = `
You are Nutrition Copilot for a health tracking app.

Suggest 2 or 3 meals that fit the user's remaining daily targets.
Return JSON only with this exact shape:
{
  "suggestions": [
    {
      "meal_name": string,
      "calories": number,
      "protein": number,
      "carbs": number,
      "fat": number,
      "fiber": number,
      "analysis_line": string
    }
  ]
}

Rules:
- Suggestions should be practical meals, not ingredients lists.
- Fit the remaining targets reasonably well, especially protein, carbs, fat, and calories.
- analysis_line must be one sentence and explain why the meal fits.
- Return 2 or 3 suggestions.
- Never wrap the JSON in markdown.
`.trim();

export interface RemainingMacros {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber?: number;
}

export interface MealSuggestion {
  meal_name: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber?: number;
  analysis_line: string;
}

export async function analyzeMeal(
  text?: string,
  imageBase64?: string,
  options?: { memoryPrior?: Record<string, unknown> | null },
): Promise<MealAnalysisResult> {
  const content = buildAnalyzeContent(text, imageBase64, options?.memoryPrior ?? null);
  const parsed = await callAnthropicJson({
    system: ANALYZE_SYSTEM_PROMPT,
    content,
  });

  return normalizeMealAnalysisResult(parsed, {
    input_text: text ?? null,
    photo_url: null,
  });
}

export async function correctMeal(
  original: MealAnalysisResult,
  correctionText: string,
): Promise<MealAnalysisResult> {
  const parsed = await callAnthropicJson({
    system: CORRECT_SYSTEM_PROMPT,
    content: [
      {
        type: 'text',
        text: [
          'Original meal analysis:',
          JSON.stringify(original, null, 2),
          '',
          `User correction: ${correctionText}`,
        ].join('\n'),
      },
    ],
  });

  return normalizeMealAnalysisResult(parsed, {
    input_text: original.input_text ?? null,
    photo_url: original.photo_url ?? null,
    meal_time: original.meal_time,
  });
}

export async function suggestMeals(
  remaining: RemainingMacros,
  context?: string,
): Promise<MealSuggestion[]> {
  const parsed = await callAnthropicJson({
    system: SUGGEST_SYSTEM_PROMPT,
    content: [
      {
        type: 'text',
        text: [
          'Remaining targets:',
          JSON.stringify(remaining, null, 2),
          context ? '' : undefined,
          context ? `Context: ${context}` : undefined,
        ]
          .filter(Boolean)
          .join('\n'),
      },
    ],
  });

  if (!parsed || typeof parsed !== 'object' || !Array.isArray(parsed.suggestions)) {
    throw new Error('Claude returned an invalid suggestions payload');
  }

  const suggestions = parsed.suggestions
    .slice(0, 3)
    .map((item: unknown) => normalizeMealSuggestion(item))
    .filter(Boolean) as MealSuggestion[];

  if (suggestions.length === 0) {
    throw new Error('Claude returned no valid meal suggestions');
  }

  return suggestions;
}

async function callAnthropicJson(input: {
  system: string;
  content: Array<Record<string, unknown>>;
}): Promise<Record<string, unknown>> {
  const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
  if (!apiKey) {
    throw new Error('ANTHROPIC_API_KEY is not configured');
  }

  const response = await fetch(ANTHROPIC_API_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: ANTHROPIC_MODEL,
      max_tokens: 900,
      temperature: 0.2,
      system: input.system,
      messages: [
        {
          role: 'user',
          content: input.content,
        },
      ],
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Anthropic request failed (${response.status}): ${errorText}`);
  }

  const payload = await response.json();
  const text = extractAnthropicText(payload);
  const parsed = parseJsonObject(text);

  if (!parsed) {
    throw new Error('Claude returned invalid JSON');
  }

  return parsed;
}

function buildAnalyzeContent(
  text?: string,
  imageBase64?: string,
  memoryPrior?: Record<string, unknown> | null,
): Array<Record<string, unknown>> {
  const content: Array<Record<string, unknown>> = [];

  if (memoryPrior) {
    content.push({
      type: 'text',
      text: [
        'Food memory prior:',
        JSON.stringify(memoryPrior, null, 2),
        'Use this as a prior when the identity match is strong, but still estimate the portion from the current input.',
      ].join('\n'),
    });
  }

  if (text) {
    content.push({
      type: 'text',
      text: `Meal description: ${text}`,
    });
  }

  if (imageBase64) {
    const image = normalizeImageSource(imageBase64);
    content.push({
      type: 'image',
      source: {
        type: 'base64',
        media_type: image.mediaType,
        data: image.data,
      },
    });
  }

  return content;
}

function normalizeMealAnalysisResult(
  input: unknown,
  overrides: Partial<MealAnalysisResult> = {},
): MealAnalysisResult {
  const record = asRecord(input);

  return {
    meal_name: readString(record.meal_name, 'Meal'),
    calories: readNumber(record.calories),
    protein: readNumber(record.protein),
    carbs: readNumber(record.carbs),
    fat: readNumber(record.fat),
    fiber: readOptionalNumber(record.fiber),
    analysis_line: readString(record.analysis_line, 'Estimated meal nutrition.'),
    confidence: clamp(readNumber(record.confidence), 0, 1),
    input_text: overrides.input_text ?? null,
    photo_url: overrides.photo_url ?? null,
    meal_time: overrides.meal_time ?? new Date().toISOString(),
  };
}

function normalizeMealSuggestion(input: unknown): MealSuggestion | null {
  const record = asRecord(input);
  const mealName = readString(record.meal_name, '');
  const analysisLine = readString(record.analysis_line, '');

  if (!mealName || !analysisLine) {
    return null;
  }

  return {
    meal_name: mealName,
    calories: readNumber(record.calories),
    protein: readNumber(record.protein),
    carbs: readNumber(record.carbs),
    fat: readNumber(record.fat),
    fiber: readOptionalNumber(record.fiber),
    analysis_line: analysisLine,
  };
}

function extractAnthropicText(payload: unknown): string {
  const record = asRecord(payload);
  const content = Array.isArray(record.content) ? record.content : [];
  const parts = content
    .map((item) => {
      const block = asRecord(item);
      return typeof block.text === 'string' ? block.text : '';
    })
    .filter(Boolean);

  return parts.join('\n').trim();
}

function parseJsonObject(text: string): Record<string, unknown> | null {
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' ? parsed as Record<string, unknown> : null;
  } catch {
    const start = text.indexOf('{');
    const end = text.lastIndexOf('}');
    if (start === -1 || end === -1 || end <= start) {
      return null;
    }

    try {
      const parsed = JSON.parse(text.slice(start, end + 1));
      return parsed && typeof parsed === 'object' ? parsed as Record<string, unknown> : null;
    } catch {
      return null;
    }
  }
}

function normalizeImageSource(imageBase64: string): { mediaType: string; data: string } {
  const dataUrlMatch = imageBase64.match(/^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$/);
  if (dataUrlMatch) {
    return {
      mediaType: dataUrlMatch[1],
      data: dataUrlMatch[2],
    };
  }

  return {
    mediaType: 'image/jpeg',
    data: imageBase64,
  };
}

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function readString(value: unknown, fallback: string): string {
  return typeof value === 'string' ? value.trim() || fallback : fallback;
}

function readNumber(value: unknown): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return roundNumber(value);
  }

  if (typeof value === 'string') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return roundNumber(parsed);
    }
  }

  return 0;
}

function readOptionalNumber(value: unknown): number | undefined {
  if (value === null || typeof value === 'undefined' || value === '') {
    return undefined;
  }

  return readNumber(value);
}

function roundNumber(value: number): number {
  return Math.round(value * 100) / 100;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}
