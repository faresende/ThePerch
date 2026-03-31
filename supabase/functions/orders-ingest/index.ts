import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
};

type IngestRequest = {
  email_id: string;
  subject: string;
  from: string;
  body: string;
  received_at: string;
};

type OrderRecord = {
  id: string;
  merchant: string;
  order_number: string;
  total: number | null;
  currency: string;
  status: string;
  source_email_id: string;
  confidence: number;
  created_at: string;
};

type ShipmentRecord = {
  id: string;
  order_id: string;
  tracking_number: string;
  carrier: string;
  status: string;
  created_at: string;
};

type ParsedOrder = {
  merchant: string;
  order_number: string;
  total: number | null;
  currency: string;
  status: string;
  confidence: number;
};

type ParsedShipment = {
  tracking_number: string;
  carrier: string;
  status: string;
};

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  try {
    const payload = normalizeRequest(await req.json());
    const parsed = parseEmail(payload);
    const supabase = createServiceClient();

    const order = await upsertOrder(supabase, payload, parsed.order);
    const shipment = parsed.shipment
      ? await upsertShipment(supabase, order.id, parsed.shipment)
      : null;

    return jsonResponse({
      order,
      shipment,
      parsed: {
        merchant: parsed.order.merchant,
        order_number: parsed.order.order_number,
        total: parsed.order.total,
        currency: parsed.order.currency,
        tracking_number: parsed.shipment?.tracking_number ?? null,
        carrier: parsed.shipment?.carrier ?? null,
      },
    });
  } catch (error) {
    return handleError(error);
  }
});

function normalizeRequest(input: unknown): IngestRequest {
  if (!isRecord(input)) {
    throw new HttpError(400, 'Request body must be a JSON object');
  }

  const payload: IngestRequest = {
    email_id: asTrimmedString(input.email_id),
    subject: asTrimmedString(input.subject),
    from: asTrimmedString(input.from),
    body: asTrimmedString(input.body),
    received_at: asTrimmedString(input.received_at),
  };

  if (!payload.email_id) throw new HttpError(400, 'email_id is required');
  if (!payload.subject) throw new HttpError(400, 'subject is required');
  if (!payload.from) throw new HttpError(400, 'from is required');
  if (!payload.body) throw new HttpError(400, 'body is required');
  if (!payload.received_at) throw new HttpError(400, 'received_at is required');

  return payload;
}

function parseEmail(payload: IngestRequest): { order: ParsedOrder; shipment: ParsedShipment | null } {
  const subject = payload.subject;
  const from = payload.from;
  const body = payload.body;
  const text = `${subject}\n${from}\n${body}`;

  const merchant = extractMerchantName(subject, from, body);
  const orderNumber = extractOrderNumber(text);
  if (!orderNumber) {
    throw new HttpError(422, 'Unable to extract order number from email');
  }

  const money = extractMoney(text);
  const shipment = extractShipment(text);

  return {
    order: {
      merchant,
      order_number: orderNumber,
      total: money.amount,
      currency: money.currency,
      status: shipment ? deriveOrderStatusFromShipment(shipment.status) : 'ordered',
      confidence: computeOrderConfidence({ merchant, orderNumber, amount: money.amount, shipment }),
    },
    shipment,
  };
}

function extractMerchantName(subject: string, from: string, body: string): string {
  const merchantPatterns = [
    /(?:thank you for shopping with|thanks for your order from|your order from)\s+([A-Z0-9][A-Za-z0-9 '&.-]{1,60})/i,
    /(?:merchant|sold by)[:\s]+([A-Z0-9][A-Za-z0-9 '&.-]{1,60})/i,
  ];

  for (const pattern of merchantPatterns) {
    const match = `${subject}\n${body}`.match(pattern);
    if (match?.[1]) {
      return cleanMerchantName(match[1]);
    }
  }

  const emailMatch = from.match(/<?(?:[^@<>\s]+)@([A-Za-z0-9.-]+)>?/);
  if (emailMatch?.[1]) {
    const hostname = emailMatch[1].replace(/^mail\./i, '');
    const domain = hostname.split('.').slice(0, -1).join('.') || hostname.split('.')[0];
    if (domain) {
      return cleanMerchantName(domain.replace(/[._-]+/g, ' '));
    }
  }

  const fallback = subject.match(/^(.+?)(?:\s+order|\s+has\s+shipped|\s+shipping|\s+receipt)/i);
  if (fallback?.[1]) {
    return cleanMerchantName(fallback[1]);
  }

  return 'Unknown Merchant';
}

function cleanMerchantName(value: string): string {
  return value
    .replace(/\b(no[- ]?reply|notifications?|support|team)\b/gi, '')
    .replace(/\b(inc|llc|ltd|gmbh|sarl|eu)\b\.?/gi, '')
    .replace(/[<>()]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function extractOrderNumber(text: string): string | null {
  const patterns = [
    /order\s*(?:number|#|no\.?)[:\s]*([A-Z0-9-]{5,})/i,
    /confirmation\s*(?:number|#)[:\s]*([A-Z0-9-]{5,})/i,
    /\b(?:order|pedido)\s+([A-Z0-9-]{5,})\b/i,
    /#([A-Z0-9-]{5,})\b/,
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (match?.[1]) {
      return match[1].trim().toUpperCase();
    }
  }

  return null;
}

function extractMoney(text: string): { amount: number | null; currency: string } {
  const patterns = [
    /(?:order total|total|amount paid)[:\s]*([$€£])?\s?(\d[\d.,]*)\s*([A-Z]{3})?/i,
    /([$€£])\s?(\d[\d.,]*)/i,
    /\b(EUR|USD|GBP)\s?(\d[\d.,]*)/i,
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (!match) continue;

    const currencyToken = [match[1], match[3]].find(Boolean) ?? match[1];
    const amountToken = match[2] ?? match[1];
    const amount = parseMoney(amountToken);
    if (amount === null) continue;

    return {
      amount,
      currency: normalizeCurrency(currencyToken),
    };
  }

  return { amount: null, currency: 'USD' };
}

function parseMoney(input: string | undefined): number | null {
  if (!input) return null;

  const trimmed = input.trim();
  if (!trimmed) return null;

  const lastComma = trimmed.lastIndexOf(',');
  const lastDot = trimmed.lastIndexOf('.');

  let normalized = trimmed.replace(/[^\d,.-]/g, '');
  if (lastComma > lastDot) {
    normalized = normalized.replace(/\./g, '').replace(',', '.');
  } else {
    normalized = normalized.replace(/,/g, '');
  }

  const amount = Number(normalized);
  return Number.isFinite(amount) ? amount : null;
}

function normalizeCurrency(input: string | undefined): string {
  const value = (input ?? '').toUpperCase();
  if (value === '$' || value === 'USD') return 'USD';
  if (value === '€' || value === 'EUR') return 'EUR';
  if (value === '£' || value === 'GBP') return 'GBP';
  return 'USD';
}

function extractShipment(text: string): ParsedShipment | null {
  const trackingPatterns = [
    /\b(1Z[0-9A-Z]{16})\b/i,
    /\b([0-9]{12,15})\b/,
    /\b([0-9]{18,22})\b/,
    /tracking\s*(?:number|#)?[:\s]*([A-Z0-9]{8,34})/i,
  ];

  let trackingNumber: string | null = null;
  for (const pattern of trackingPatterns) {
    const match = text.match(pattern);
    if (match?.[1]) {
      trackingNumber = match[1].trim().toUpperCase();
      break;
    }
  }

  if (!trackingNumber) {
    return null;
  }

  const carrier = extractCarrier(text, trackingNumber);
  const status = extractShipmentStatus(text);

  return {
    tracking_number: trackingNumber,
    carrier,
    status,
  };
}

function extractCarrier(text: string, trackingNumber: string): string {
  const carrierMatch = text.match(/\b(UPS|FedEx|DHL|USPS|Amazon Logistics|Amazon|OnTrac|LaserShip)\b/i);
  if (carrierMatch?.[1]) {
    return carrierMatch[1].toUpperCase().replace(/\s+/g, ' ');
  }

  if (/^1Z/i.test(trackingNumber)) return 'UPS';
  if (/^\d{12,15}$/.test(trackingNumber)) return 'FEDEX';
  if (/^\d{20,22}$/.test(trackingNumber)) return 'USPS';
  return 'UNKNOWN';
}

function extractShipmentStatus(text: string): string {
  const normalized = text.toLowerCase();

  if (normalized.includes('delivered')) return 'delivered';
  if (normalized.includes('out for delivery')) return 'out_for_delivery';
  if (normalized.includes('in transit') || normalized.includes('on the way')) return 'in_transit';
  if (normalized.includes('shipped') || normalized.includes('shipping') || normalized.includes('label created')) {
    return 'label_created';
  }

  return 'label_created';
}

function deriveOrderStatusFromShipment(shipmentStatus: string): string {
  switch (shipmentStatus) {
    case 'delivered':
      return 'delivered';
    case 'out_for_delivery':
    case 'in_transit':
    case 'label_created':
      return 'shipped';
    default:
      return 'ordered';
  }
}

function computeOrderConfidence(input: {
  merchant: string;
  orderNumber: string;
  amount: number | null;
  shipment: ParsedShipment | null;
}): number {
  let confidence = 0.55;
  if (input.merchant !== 'Unknown Merchant') confidence += 0.15;
  if (input.orderNumber.length >= 5) confidence += 0.15;
  if (input.amount !== null) confidence += 0.1;
  if (input.shipment) confidence += 0.05;
  return Math.min(0.99, confidence);
}

async function upsertOrder(
  supabase: ReturnType<typeof createServiceClient>,
  payload: IngestRequest,
  order: ParsedOrder,
): Promise<OrderRecord> {
  const { data: existingByEmail, error: existingByEmailError } = await supabase
    .from('orders')
    .select('*')
    .eq('source_email_id', payload.email_id)
    .maybeSingle();

  if (existingByEmailError) {
    throw new HttpError(500, `Failed to look up order by email: ${existingByEmailError.message}`);
  }

  if (existingByEmail) {
    return existingByEmail as OrderRecord;
  }

  const insertPayload = {
    merchant: order.merchant,
    order_number: order.order_number,
    total: order.total,
    currency: order.currency,
    status: order.status,
    source_email_id: payload.email_id,
    confidence: order.confidence,
    created_at: payload.received_at,
  };

  const { data, error } = await supabase
    .from('orders')
    .upsert(insertPayload, { onConflict: 'merchant,order_number' })
    .select('*')
    .single();

  if (error || !data) {
    throw new HttpError(500, `Failed to write order: ${error?.message ?? 'unknown error'}`);
  }

  return data as OrderRecord;
}

async function upsertShipment(
  supabase: ReturnType<typeof createServiceClient>,
  orderId: string,
  shipment: ParsedShipment,
): Promise<ShipmentRecord> {
  const { data, error } = await supabase
    .from('shipments')
    .upsert(
      {
        order_id: orderId,
        tracking_number: shipment.tracking_number,
        carrier: shipment.carrier,
        status: shipment.status,
      },
      { onConflict: 'order_id,tracking_number' },
    )
    .select('*')
    .single();

  if (error || !data) {
    throw new HttpError(500, `Failed to write shipment: ${error?.message ?? 'unknown error'}`);
  }

  return data as ShipmentRecord;
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

function asTrimmedString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
    this.name = 'HttpError';
  }
}
