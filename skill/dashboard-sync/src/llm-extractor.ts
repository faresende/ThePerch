/**
 * llm-extractor.ts
 *
 * LLM-based fallback for the orders-autopilot pipeline. Used when the
 * keyword/regex classifier is uncertain — typically when:
 *   - Tier 1 returned merchant_name == prettifyDomain(senderDomain),
 *     i.e. nothing better than the bare sender domain.
 *   - subject signals "order ... confirmed" but no order_number was
 *     extracted by regex.
 *   - confidence is in the ambiguous 0.5–0.8 zone.
 *
 * Strategy: ask a small local model (Ollama qwen2.5:14b) for a strict
 * JSON object containing merchant_name, order_number, total_amount,
 * currency, and is_purchase_confirmation. If Ollama is unreachable or
 * returns garbage, fall back to Anthropic's Haiku tier (still cheap).
 *
 * Cost: Ollama is free + local. Anthropic fallback is ~$0.001/email at
 * Haiku rates. Both negligible for ~50 orders/month.
 */
import http from 'node:http';

export interface LLMExtractedFields {
  merchant_name: string | null;
  order_number: string | null;
  total_amount: number | null;
  currency: string | null;
  is_purchase_confirmation: boolean;
  confidence: number; // 0..1
  source: 'ollama' | 'anthropic' | 'failed';
}

const OLLAMA_HOST = process.env.OLLAMA_HOST || 'http://localhost:11434';
const OLLAMA_MODEL = process.env.OLLAMA_ORDERS_MODEL || 'qwen2.5:14b';

const SYSTEM_PROMPT = `You are an email parser. The user pastes the subject + body of an email; you reply with ONLY a single JSON object describing whether it's an order confirmation and, if so, the merchant + order details.

Reply schema (no prose, no markdown, no code fences):
{
  "merchant_name": string | null,    // The retailer / merchant. "Body&Fit", "Apple", "Hardgraft", etc. Drop generic suffixes ("Customer Service", "Support"). null if you can't tell.
  "order_number": string | null,     // Order/reference number. Strip leading "#". null if absent.
  "total_amount": number | null,     // The ORDER TOTAL (final amount paid), not a line item or subtotal. Numeric, no currency symbol. null if absent.
  "currency": string | null,         // 3-letter ISO code: "EUR" / "USD" / "GBP" / "BRL" / "JPY" etc. null if you can't tell.
  "is_purchase_confirmation": boolean, // true if this is a purchase/order confirmation. false for shipping notices, marketing, newsletters, receipts of unrelated services.
  "confidence": number               // 0.0 to 1.0 — how sure you are about the above. 0.95+ = obvious, 0.5–0.7 = ambiguous, <0.4 = guess.
}

Rules:
- ONLY output the JSON object. No explanation. No "Here is the result:".
- For order_number, extract the merchant's order/reference number, not a tracking number.
- If multiple amounts appear, the total is usually the largest and labeled "Total" / "Grand Total" / "Order Total".`;

interface OllamaResponse {
  model: string;
  response: string;
  done: boolean;
}

function ollamaRequest(prompt: string, timeoutMs: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const url = new URL(`${OLLAMA_HOST}/api/generate`);
    const body = JSON.stringify({
      model: OLLAMA_MODEL,
      prompt,
      system: SYSTEM_PROMPT,
      format: 'json',
      stream: false,
      options: { temperature: 0.1, num_predict: 400 },
    });
    const req = http.request(
      {
        hostname: url.hostname,
        port: url.port || 11434,
        path: url.pathname,
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
      },
      (res) => {
        let data = '';
        res.on('data', (chunk) => { data += chunk; });
        res.on('end', () => {
          if (res.statusCode !== 200) {
            reject(new Error(`Ollama HTTP ${res.statusCode}: ${data.slice(0, 200)}`));
            return;
          }
          try {
            const parsed = JSON.parse(data) as OllamaResponse;
            resolve(parsed.response);
          } catch (e) {
            reject(new Error(`Ollama returned non-JSON: ${data.slice(0, 200)}`));
          }
        });
      },
    );
    req.on('error', reject);
    req.setTimeout(timeoutMs, () => {
      req.destroy(new Error(`Ollama timed out after ${timeoutMs}ms`));
    });
    req.write(body);
    req.end();
  });
}

function buildUserPrompt(subject: string, sender: string, body: string): string {
  // Trim body to keep latency reasonable. The first 4000 chars almost
  // always contain merchant + total + order number.
  const trimmedBody = body.slice(0, 4000);
  return `Email to classify:

From: ${sender}
Subject: ${subject}

Body:
${trimmedBody}`;
}

function safeParse(raw: string): Partial<LLMExtractedFields> | null {
  // qwen sometimes wraps JSON in code fences despite format:'json'
  const cleaned = raw.replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/i, '').trim();
  try {
    return JSON.parse(cleaned);
  } catch {
    // Try to find the first {...} block
    const m = cleaned.match(/\{[\s\S]*\}/);
    if (m) {
      try { return JSON.parse(m[0]); } catch { /* fall through */ }
    }
    return null;
  }
}

/**
 * Run the LLM extractor over an email. Returns null if both providers
 * fail (caller falls back to whatever Tier 1 produced).
 */
export async function extractWithLLM(
  subject: string,
  sender: string,
  body: string,
): Promise<LLMExtractedFields | null> {
  const userPrompt = buildUserPrompt(subject, sender, body);

  // Try Ollama first.
  try {
    const raw = await ollamaRequest(userPrompt, 30_000);
    const parsed = safeParse(raw);
    if (parsed && typeof parsed === 'object') {
      return {
        merchant_name: typeof parsed.merchant_name === 'string' ? parsed.merchant_name : null,
        order_number: typeof parsed.order_number === 'string' ? parsed.order_number : null,
        total_amount: typeof parsed.total_amount === 'number' ? parsed.total_amount : null,
        currency: typeof parsed.currency === 'string' ? parsed.currency : null,
        is_purchase_confirmation: !!parsed.is_purchase_confirmation,
        confidence: typeof parsed.confidence === 'number' ? Math.min(1, Math.max(0, parsed.confidence)) : 0.5,
        source: 'ollama',
      };
    }
  } catch (e) {
    // Log and try Anthropic fallback below
    console.error(`[llm-extractor] Ollama failed: ${e instanceof Error ? e.message : e}`);
  }

  // Anthropic fallback. Only fires when ANTHROPIC_API_KEY is set AND
  // Ollama failed; otherwise we return null and let the caller use Tier 1.
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return null;
  try {
    const body = JSON.stringify({
      model: 'claude-haiku-4-5',
      max_tokens: 400,
      system: SYSTEM_PROMPT,
      messages: [{ role: 'user', content: userPrompt }],
    });
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body,
    });
    if (!res.ok) {
      const txt = await res.text();
      console.error(`[llm-extractor] Anthropic HTTP ${res.status}: ${txt.slice(0, 200)}`);
      return null;
    }
    const json = await res.json() as { content?: Array<{ text?: string }> };
    const text = json.content?.[0]?.text || '';
    const parsed = safeParse(text);
    if (!parsed) return null;
    return {
      merchant_name: typeof parsed.merchant_name === 'string' ? parsed.merchant_name : null,
      order_number: typeof parsed.order_number === 'string' ? parsed.order_number : null,
      total_amount: typeof parsed.total_amount === 'number' ? parsed.total_amount : null,
      currency: typeof parsed.currency === 'string' ? parsed.currency : null,
      is_purchase_confirmation: !!parsed.is_purchase_confirmation,
      confidence: typeof parsed.confidence === 'number' ? Math.min(1, Math.max(0, parsed.confidence)) : 0.5,
      source: 'anthropic',
    };
  } catch (e) {
    console.error(`[llm-extractor] Anthropic fallback failed: ${e instanceof Error ? e.message : e}`);
    return null;
  }
}
