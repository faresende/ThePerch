export interface AnalyzeRequest {
  mode: 'analyze';
  user_id: string;
  text?: string;
  image_base64?: string;
}

export interface CorrectRequest {
  mode: 'correct';
  record_id: string;
  correction_text: string;
}

export interface SuggestRequest {
  mode: 'suggest';
  user_id: string;
  context?: string;
}

export interface MealAnalysisResult {
  meal_name: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  fiber?: number;
  analysis_line: string;
  confidence: number;
  input_text?: string | null;
  photo_url?: string | null;
  meal_time: string;
}

export function normalizeAnalyzeRequest(input: Record<string, unknown>): AnalyzeRequest {
  const user_id = typeof input.user_id === 'string' ? input.user_id.trim() : '';
  const text = typeof input.text === 'string' ? input.text.trim() : undefined;
  const image_base64 = typeof input.image_base64 === 'string' ? input.image_base64.trim() : undefined;

  if (!user_id) throw new Error('user_id is required');
  if (!text && !image_base64) throw new Error('analyze mode requires text or image_base64');

  return {
    mode: 'analyze',
    user_id,
    text,
    image_base64,
  };
}

export function normalizeCorrectRequest(input: Record<string, unknown>): CorrectRequest {
  const record_id = typeof input.record_id === 'string' ? input.record_id.trim() : '';
  const correction_text = typeof input.correction_text === 'string' ? input.correction_text.trim() : '';

  if (!record_id) throw new Error('record_id is required');
  if (!correction_text) throw new Error('correction_text is required');

  return {
    mode: 'correct',
    record_id,
    correction_text,
  };
}

export function normalizeSuggestRequest(input: Record<string, unknown>): SuggestRequest {
  const user_id = typeof input.user_id === 'string' ? input.user_id.trim() : '';
  const context = typeof input.context === 'string' ? input.context.trim() : undefined;

  if (!user_id) throw new Error('user_id is required');

  return {
    mode: 'suggest',
    user_id,
    context,
  };
}

export function mealRecordPayload(input: { userId: string; analysis: MealAnalysisResult }) {
  const { userId, analysis } = input;

  return {
    user_id: userId,
    type: 'measurement',
    category: 'health',
    title: analysis.meal_name,
    display_hint: 'meal_log',
    data: {
      meal_name: analysis.meal_name,
      calories: analysis.calories,
      protein: analysis.protein,
      carbs: analysis.carbs,
      fat: analysis.fat,
      fiber: analysis.fiber ?? null,
      analysis: analysis.analysis_line,
      photo_url: analysis.photo_url ?? null,
      corrected: false,
      correction_history: [],
      input_text: analysis.input_text ?? null,
      meal_time: analysis.meal_time,
      confidence: analysis.confidence,
    },
  };
}
