import type { OrderData, ShipmentData } from './types';

export function normalizeMerchantName(name: string): string {
  return name
    .toLowerCase()
    .replace(/eu\s+s\.a\s*r\.l\.?/g, '')
    .replace(/\bs\.a\s*r\.l\.?\b/g, '')
    .replace(/\bsarl\b/g, '')
    .replace(/\blda\.?\b/g, '')
    .replace(/\bllc\b/g, '')
    .replace(/\binc\.?\b/g, '')
    .replace(/\bgmbh\b/g, '')
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function extractOrderCandidate(text: string): OrderData | null {
  if (!text) return null;

  const orderNumberMatch = text.match(/order\s+number[:\s]+([A-Z0-9-]{6,})/i);
  const totalMatch = text.match(/(?:total[:\s]+|eur\s*)(\d+(?:[\.,]\d{2})?)/i);
  const currencyMatch = text.match(/\b(EUR|USD|GBP)\b/i);
  const merchantMatch = text.match(/merchant[:\s]+(.+)/i);
  const orderedDateMatch = text.match(/ordered\s+on\s+(\d{4}-\d{2}-\d{2})/i);
  const placedLanguage = /order has been placed|purchase confirmation|thanks for your order/i.test(text);

  if (!orderNumberMatch || !placedLanguage) return null;

  const merchantName = merchantMatch?.[1]?.trim() || 'Unknown merchant';
  const totalAmount = totalMatch ? parseFloat(totalMatch[1].replace(',', '.')) : undefined;

  return {
    merchant_name: merchantName,
    normalized_merchant: normalizeMerchantName(merchantName),
    order_number: orderNumberMatch[1],
    order_date: orderedDateMatch?.[1] || new Date().toISOString().slice(0, 10),
    total_amount: totalAmount ?? null,
    currency: currencyMatch?.[1]?.toUpperCase() ?? 'USD',
    source_email_ids: [],
    confidence_score: 0.9,
    status: 'ordered',
  };
}

export function extractShipmentCandidate(text: string): ShipmentData | null {
  if (!text) return null;

  const trackingMatch =
    text.match(/tracking\s*(?:number)?[:\s]+([A-Z0-9]{10,})/i) ||
    text.match(/\b(1Z[0-9A-Z]{16})\b/i) ||
    text.match(/\b([0-9]{18,})\b/);

  if (!trackingMatch) return null;

  const carrierMatch = text.match(/\b(UPS|FedEx|DHL|USPS|DPD|Amazon)\b/i);
  const merchantMatch = text.match(/merchant[:\s]+(.+)/i);
  const orderNumberMatch = text.match(/order\s+number[:\s]+([A-Z0-9-]{6,})/i);
  const normalizedText = text.toLowerCase();
  const merchantName = merchantMatch?.[1]?.trim();

  let status: ShipmentData['status'] = 'unknown';
  if (normalizedText.includes('out for delivery')) status = 'out_for_delivery';
  else if (normalizedText.includes('in transit')) status = 'in_transit';
  else if (normalizedText.includes('delivered')) status = 'delivered';
  else if (normalizedText.includes('label created')) status = 'label_created';
  else if (normalizedText.includes('exception')) status = 'exception';

  return {
    merchant_name: merchantName,
    normalized_merchant: merchantName ? normalizeMerchantName(merchantName) : undefined,
    order_number: orderNumberMatch?.[1],
    tracking_number: trackingMatch[1],
    carrier: carrierMatch?.[1]?.toUpperCase() || 'UNKNOWN',
    provider: 'email',
    status,
    latest_checkpoint: null,
    shipped_at: null,
    delivered_at: null,
    source_email_ids: [],
    confidence_score: 0.88,
  };
}
