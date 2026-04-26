/**
 * email-classifier.ts
 * Classifies emails as purchase_confirmation vs shipping_notification vs other.
 * Uses keyword + signal analysis for classification.
 */

export type EmailType = 'purchase_confirmation' | 'shipping_notification' | 'other';

interface EmailSignals {
  isPurchase: boolean;
  isShipping: boolean;
  /** Raw summed weight from purchase keyword + merchant-domain matches. */
  purchaseScore: number;
  /** Raw summed weight from shipping keyword matches. */
  shippingScore: number;
  confidence: number;
  matchedKeywords: string[];
}

/**
 * Senders whose emails are never tangible-goods orders even when they contain
 * order/total keywords. Food delivery, ride-hailing, meal subscriptions, etc.
 * Match is substring on the lowercased sender email. Kept small and specific;
 * a 10X pass should replace this with a proper allowlist/blocklist table.
 */
const NON_GOODS_SENDERS: string[] = [
  'uber.com', 'ubereats.com', 'uber-receipts', 'uber receipts',
  'glovo', 'deliveroo', 'just-eat', 'justeat', 'doordash', 'grubhub',
  'bolt-food', 'boltfood', 'freenow',
  'lyft.com',
  'sendcloud', 'loox.io',
  // Stripe / billing / receipts platforms; real orders come from the merchant, not the processor.
  'stripe.com',
];

function isNonGoodsSender(senderEmail: string): boolean {
  const s = senderEmail.toLowerCase();
  return NON_GOODS_SENDERS.some(pat => s.includes(pat));
}

/**
 * Classifies an email body as purchase or shipping type.
 */
export function classifyEmail(
  subject: string,
  body: string,
  senderEmail: string,
): { type: EmailType; confidence: number } {
  if (isNonGoodsSender(senderEmail)) {
    return { type: 'other', confidence: 1 };
  }
  const lowerSender = senderEmail.toLowerCase();

  // Subject takes priority: a clear "order ... confirmed" / "thanks for
  // your order" in the subject means PURCHASE confirmation regardless of
  // what's in the body. This catches cases like Hardgraft where the
  // order-confirmation email also embeds a tracking number — body
  // shipping signals would otherwise win and route to shipping.
  const subjectSignals = analyzeSignals(subject.toLowerCase(), lowerSender);
  if (subjectSignals.isPurchase && subjectSignals.purchaseScore >= 0.85) {
    return { type: 'purchase_confirmation', confidence: Math.min(subjectSignals.confidence, 1) };
  }

  const text = `${subject} ${body}`.toLowerCase();
  const signals = analyzeSignals(text, lowerSender);

  if (signals.isPurchase && signals.isShipping) {
    // Both signals — compare RAW summed scores so ties are rare. Order
    // confirmations from real merchants almost always carry some shipping
    // language too (tracking, delivery date, carrier hint). Without
    // numeric scoring those tie at 1-vs-1 and the email gets dumped to
    // "other", which silently drops orders. Using the raw sums lets
    // "Order #X confirmed" beat "tracking number TBD" cleanly.
    if (signals.purchaseScore > signals.shippingScore) {
      return { type: 'purchase_confirmation', confidence: signals.confidence };
    } else if (signals.shippingScore > signals.purchaseScore) {
      return { type: 'shipping_notification', confidence: signals.confidence };
    }
    // Genuine tie — prefer purchase since shipping notifications without
    // a clear purchase signal are rare. Better to land in orders and let
    // the extractor demote to review_item than to silently skip.
    return { type: 'purchase_confirmation', confidence: signals.confidence * 0.6 };
  }

  if (signals.isPurchase) {
    return { type: 'purchase_confirmation', confidence: signals.confidence };
  }

  if (signals.isShipping) {
    return { type: 'shipping_notification', confidence: signals.confidence };
  }

  return { type: 'other', confidence: signals.confidence };
}

function analyzeSignals(text: string, senderEmail: string): EmailSignals {
  const purchaseSignals: Array<{ keyword: string; weight: number }> = [
    { keyword: 'order confirmed', weight: 0.9 },
    { keyword: 'order is confirmed', weight: 0.9 },
    { keyword: 'order has been confirmed', weight: 0.9 },
    { keyword: 'order has been received', weight: 0.85 },
    { keyword: 'we received your order', weight: 0.85 },
    { keyword: "we've received your order", weight: 0.85 },
    { keyword: "we've got your order", weight: 0.85 },
    { keyword: 'order number', weight: 0.8 },
    { keyword: 'order #', weight: 0.8 },
    { keyword: 'thank you for your order', weight: 0.9 },
    { keyword: 'thanks for your order', weight: 0.9 },
    { keyword: 'thanks for your purchase', weight: 0.9 },
    { keyword: 'purchase confirmed', weight: 0.9 },
    { keyword: 'order received', weight: 0.8 },
    { keyword: 'order placed', weight: 0.85 },
    { keyword: 'confirmation of order', weight: 0.85 },
    { keyword: 'order confirmation', weight: 0.85 },
    { keyword: 'your order is being processed', weight: 0.85 },
    { keyword: 'payment for', weight: 0.7 },
    { keyword: 'payment received', weight: 0.85 },
    { keyword: 'payment for #', weight: 0.85 },
    { keyword: 'total:', weight: 0.5 },
    { keyword: 'subtotal:', weight: 0.5 },
    { keyword: 'order total', weight: 0.7 },
    { keyword: 'payment confirmed', weight: 0.8 },
    { keyword: 'invoice', weight: 0.5 },
    { keyword: 'receipt', weight: 0.5 },
    { keyword: 'confirmation', weight: 0.4 },
  ];

  const shippingSignals: Array<{ keyword: string; weight: number }> = [
    { keyword: 'tracking number', weight: 0.95 },
    { keyword: 'tracking', weight: 0.7 },
    { keyword: 'shipped', weight: 0.85 },
    { keyword: 'out for delivery', weight: 0.95 },
    { keyword: 'delivered', weight: 0.8 },
    { keyword: 'shipping notification', weight: 0.9 },
    { keyword: 'package shipped', weight: 0.9 },
    { keyword: 'your package', weight: 0.75 },
    { keyword: 'carrier', weight: 0.5 },
    { keyword: 'dhl', weight: 0.4 },
    { keyword: 'fedex', weight: 0.4 },
    { keyword: 'ups', weight: 0.4 },
    { keyword: 'usps', weight: 0.4 },
    { keyword: 'royal mail', weight: 0.4 },
    { keyword: 'in transit', weight: 0.8 },
    { keyword: 'arriving', weight: 0.6 },
    { keyword: 'delivery', weight: 0.5 },
    { keyword: 'estimated delivery', weight: 0.85 },
    { keyword: 'expected delivery', weight: 0.85 },
  ];

  // Known merchant patterns (from existing deliveries). Substring match on
  // sender email — extend whenever a new merchant ends up classified as
  // "other" in production logs.
  const knownPurchaseDomains: Record<string, string> = {
    'amazon': 'Amazon',
    'zara': 'Zara',
    'nike': 'Nike',
    'apple': 'Apple',
    'bestbuy': 'Best Buy',
    'ebay': 'eBay',
    'aliexpress': 'AliExpress',
    'shein': 'Shein',
    'asics': 'ASICS',
    'net-a-porter': 'Net-A-Porter',
    'ssense': 'Ssense',
    'farfetch': 'Farfetch',
    'endclothing': 'END.',
    'superdry': 'Superdry',
    'uniqlo': 'Uniqlo',
    'decathlon': 'Decathlon',
    'mediamarkt': 'MediaMarkt',
    'fnac': 'Fnac',
    'worten': 'Worten',
    'rackstore': 'RackStore',
    // Apparel + EDC merchants Fábio orders from regularly
    'hardgraft': 'Hardgraft',
    'jacquesmariemage': 'Jacques Marie Mage',
    'vulkit': 'Vulkit',
    'bodyandfit': 'Body&Fit',
    'matadorequipment': 'Matador',
    'matadorup': 'Matador',
    'vollebak': 'Vollebak',
    'mukama': 'Mukama',
    'lofree': 'Lofree',
    'nextsense': 'NextSense',
    'loveandtogether': 'Love&Together',
    'mrporter': 'MR PORTER',
    // Shopify-hosted shops; sender often store+...@t.shopifyemail.com so
    // the boost runs for any Shopify-routed merchant. Real merchant name
    // gets recovered downstream from the email body.
    'shopifyemail': 'Shopify Merchant',
  };

  let purchaseScore = 0;
  let shippingScore = 0;
  const matchedKeywords: string[] = [];

  for (const signal of purchaseSignals) {
    if (text.includes(signal.keyword)) {
      purchaseScore += signal.weight;
      matchedKeywords.push(signal.keyword);
    }
  }

  for (const signal of shippingSignals) {
    if (text.includes(signal.keyword)) {
      shippingScore += signal.weight;
      matchedKeywords.push(signal.keyword);
    }
  }

  // Catch-all regex for "order [#XYZ / has been / is] confirmed" phrasings
  // that the literal-keyword list misses. Real-world subject lines like
  //   "Order #108984 confirmed"
  //   "hardgraft order HGMC20117325 confirmed"
  //   "Your Body&Fit order is confirmed!"
  // all read as orders to a human but skip the literal "order confirmed".
  // Single fire (not stacking) so we don't double-count if both this regex
  // and the literal "order confirmed" hit.
  if (/order(?:\s+[#a-z0-9-]{2,30}){0,3}\s+(?:is\s+|has\s+been\s+)?confirmed/i.test(text)
      && !matchedKeywords.includes('order confirmed')) {
    purchaseScore += 0.85;
    matchedKeywords.push('order_confirmed_regex');
  }

  // Boost purchase score for known merchant domains. Generous list — false
  // positives here just slightly elevate a merchant's score, real false
  // positives still need to clear the keyword threshold on their own.
  for (const [domain, merchant] of Object.entries(knownPurchaseDomains)) {
    if (senderEmail.includes(domain)) {
      purchaseScore += 0.5;
    }
  }

  const maxScore = Math.max(purchaseScore, shippingScore, 1);
  const confidence = Math.min(maxScore, 1.0);

  return {
    isPurchase: purchaseScore >= 0.8,
    isShipping: shippingScore >= 0.8,
    purchaseScore,
    shippingScore,
    confidence,
    matchedKeywords,
  };
}

/**
 * Extracts order fields from a purchase confirmation email.
 */
export function extractOrderFields(
  subject: string,
  body: string,
  senderEmail: string,
  emailId: string,
): {
  merchantName: string;
  normalizedMerchant: string;
  orderNumber: string | null;
  orderDate: Date | null;
  totalAmount: number | null;
  currency: string;
  confidence: number;
} {
  const signals = analyzeSignals(`${subject} ${body}`.toLowerCase(), senderEmail.toLowerCase());

  // Extract merchant name from sender
  const senderDomain = senderEmail.split('@')[1]?.replace(/^www\./, '').split('.')[0] || 'Unknown';
  const merchantName = inferMerchantName(senderEmail, subject, body) || senderDomain;

  // Extract order number
  const orderNumber = extractOrderNumber(subject, body);

  // Extract total amount
  const { amount, currency } = extractTotal(body);

  // Extract order date
  const orderDate = extractOrderDate(body) || new Date();

  return {
    merchantName,
    normalizedMerchant: normalizeMerchant(merchantName),
    orderNumber,
    orderDate,
    totalAmount: amount,
    currency,
    confidence: signals.confidence,
  };
}

/**
 * Extracts shipment fields from a shipping notification email.
 */
export function extractShipmentFields(
  subject: string,
  body: string,
  senderEmail: string,
  emailId: string,
): {
  trackingNumber: string | null;
  carrier: string | null;
  status: string;
  shippedAt: Date | null;
  confidence: number;
} {
  const signals = analyzeSignals(`${subject} ${body}`.toLowerCase(), senderEmail.toLowerCase());

  // Extract tracking number
  const trackingNumber = extractTrackingNumber(subject, body);

  // Infer carrier
  const carrier = inferCarrier(trackingNumber, body, senderEmail);

  // Determine shipped_at
  const shippedAt = extractShippedDate(body) || new Date();

  // Determine status
  let status = 'unknown';
  const text = `${subject} ${body}`.toLowerCase();
  if (text.includes('delivered')) status = 'delivered';
  else if (text.includes('out for delivery')) status = 'out_for_delivery';
  else if (text.includes('in transit') || text.includes('shipped')) status = 'in_transit';
  else if (text.includes('label created') || trackingNumber) status = 'label_created';
  else if (text.includes('exception') || text.includes('failed')) status = 'exception';

  return {
    trackingNumber,
    carrier,
    status,
    shippedAt,
    confidence: signals.confidence,
  };
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function inferMerchantName(sender: string, subject: string, body: string): string | null {
  const known: Record<string, string> = {
    'amazon': 'Amazon',
    'amazon.com': 'Amazon',
    'zara': 'Zara',
    'nike': 'Nike',
    'apple': 'Apple',
    'bestbuy': 'Best Buy',
    'ebay': 'eBay',
    'aliexpress': 'AliExpress',
    'shein': 'SHEIN',
    'asics': 'ASICS',
    'netaporter': 'Net-A-Porter',
    'farfetch': 'Farfetch',
    'ssense': 'Ssense',
    'superdry': 'Superdry',
    'uniqlo': 'UNIQLO',
    'decathlon': 'Decathlon',
    'mediamarkt': 'MediaMarkt',
    'fnac': 'Fnac',
    'worten': 'Worten',
    'rackstore': 'RackStore',
    // Apparel + EDC merchants Fábio orders from regularly
    'hardgraft': 'Hardgraft',
    'jacquesmariemage': 'Jacques Marie Mage',
    'vulkit': 'Vulkit',
    'bodyandfit': 'Body&Fit',
    'matadorequipment': 'Matador',
    'matadorup': 'Matador',
    'vollebak': 'Vollebak',
    'mukama': 'Mukama',
    'lofree': 'Lofree',
    'nextsense': 'NextSense',
    'loveandtogether': 'Love&Together',
    'mrporter': 'MR PORTER',
  };

  const lower = sender.toLowerCase();
  for (const [domain, name] of Object.entries(known)) {
    if (lower.includes(domain)) return name;
  }

  // Shopify-routed senders (`store+xyz@t.shopifyemail.com`) hide the real
  // merchant from the sender field. Recover from the body in 3 ways
  // (cheapest to most heuristic):
  if (lower.includes('shopifyemail')) {
    // 1. Look for any known merchant domain in body URLs (most reliable —
    //    Shopify confirmation emails always include `<merchant>.com/orders/`
    //    or `<merchant>.eu/...` links).
    for (const [domain, name] of Object.entries(known)) {
      if (body.toLowerCase().includes(domain)) return name;
    }
    // 2. First non-trivial capitalized phrase after "Thank you for your
    //    purchase" or "from ". Catches "Matador Equipment EU".
    const phraseMatch = body.match(
      /(?:thank you for your (?:purchase|order)!?\s*\*+\s*\n*\s*|from\s+)([A-Z][A-Za-z0-9][A-Za-z0-9 &.'-]{2,30})/,
    );
    if (phraseMatch) return phraseMatch[1].trim();
    // 3. <title>...</title> if HTML body, stripping any "Order #X — " prefix.
    const headerMatch = body.match(/<title>([^<]+)<\/title>/i);
    if (headerMatch) {
      const cleaned = headerMatch[1].replace(/^order\s+#?\S+\s*[\-:|]\s*/i, '').trim();
      if (cleaned && !/^order/i.test(cleaned)) return cleaned;
    }
  }

  // Reject "subject extraction" when the leading word is a generic
  // possessive or order keyword — better to fall through to the sender
  // domain than save a junk name like "Your" or "Order".
  const subjectMatch = subject.match(/^([A-Za-z][A-Za-z\s&'-]+?)\s/);
  if (subjectMatch) {
    const candidate = subjectMatch[1].trim();
    const lowerCand = candidate.toLowerCase();
    const junkLeads = new Set([
      'your', 'order', 'thank', 'thanks', 'we', 'a', 'the', 'hi', 'hello',
      'welcome', 'confirmation', 'receipt', 'payment',
    ]);
    if (!junkLeads.has(lowerCand)) return candidate;
  }

  return null;
}

function normalizeMerchant(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '')
    .trim();
}

function extractOrderNumber(subject: string, body: string): string | null {
  // Strip obvious HTML attributes before regex so we don't match things like
  // cellpadding="0" or style="..." as order numbers. Cheap and effective.
  const strip = (s: string) =>
    s
      .replace(/cellpadding\s*=\s*["']?[^"'>\s]*/gi, '')
      .replace(/cellspacing\s*=\s*["']?[^"'>\s]*/gi, '')
      .replace(/bgcolor\s*=\s*["']?[^"'>\s]*/gi, '')
      .replace(/class\s*=\s*["'][^"']*["']/gi, '')
      .replace(/style\s*=\s*["'][^"']*["']/gi, '')
      .replace(/<[^>]+>/g, ' ');
  const subj = strip(subject);
  const bod = strip(body);

  // Patterns in order of specificity. The earlier patterns fire when a
  // "#" or "order number"/"order no" anchor is present; the later ones
  // are more permissive and run only if those miss.
  const patterns: RegExp[] = [
    // "Order #AB-12345678"
    /order\s*#\s*([A-Z0-9][A-Z0-9-]{4,24})/i,
    // "order number: AB-12345678"
    /order\s+number\s*[:#]?\s*([A-Z0-9][A-Z0-9-]{4,24})/i,
    // "order no. 12345678"
    /order\s+no\.?\s*([A-Z0-9][A-Z0-9-]{4,24})/i,
    // Amazon-style "order 123-1234567-1234567"
    /order\s+(\d{3}-\d{7}-\d{7})/i,
    // "order HGMC20117325" / "order ABC-12345" — bare token after "order"
    // (no # required). Restricted to merchant-style prefixes (≥2 letters,
    // ≥1 digit somewhere) so we don't scoop "order details" or "order
    // confirmation".
    /order\s+([A-Z]{2,}[A-Z0-9-]*[0-9][A-Z0-9-]*)/,
    // "Order 1723 confirmed" — pure-numeric Shopify-style. Constrained
    // to "order <digits> confirmed" so common phrases don't match.
    /order\s+(\d{3,8})\s+confirmed/i,
    // "#ORD-12345678" (must start with an alpha prefix to avoid catching random tokens)
    /#([A-Z]{2,}[A-Z0-9-]{3,24})/i,
  ];

  // Tokens we should never accept as an order number — common HTML/CSS
  // attributes + pure 6-char hex colors that slip through `#XYZ` patterns.
  const isHtmlJunk = (v: string) =>
    /^(CELLPADDING|CELLSPACING|BGCOLOR|BORDER|ALIGN|VALIGN|WIDTH|HEIGHT|FONT|COLOR|STYLE|CLASS|UTF|HTML|BODY|TABLE|DIV|SPAN|HEADER|FOOTER)$/.test(v) ||
    /^[0-9A-F]{3}$/.test(v) ||
    /^[0-9A-F]{6}$/.test(v) ||
    /^[0-9A-F]{8}$/.test(v);

  for (const pattern of patterns) {
    const m = subj.match(pattern) || bod.match(pattern);
    if (m && m[1]) {
      const v = m[1].toUpperCase();
      if (!isHtmlJunk(v)) return v;
    }
  }
  return null;
}

function extractTrackingNumber(subject: string, body: string): string | null {
  const text = `${subject} ${body}`;
  // Common tracking number patterns
  const patterns = [
    /\b(1Z[A-Z0-9]{16})\b/i,                    // UPS
    /\b(94[0-9]{20})\b/,                        // FedEx
    /\b(EA[0-9]{18})\b/i,                       // DHL
    /\b([0-9]{12,22})\b/,                       // Generic numeric
    /\b([A-Z]{2}[0-9]{9}[A-Z]{2})\b/,          // USPS
    /\b([A-Z][0-9]{9}[A-Z]{2})\b/i,             // Royal Mail
  ];

  for (const pattern of patterns) {
    const m = text.match(pattern);
    if (m) return m[1].toUpperCase();
  }
  return null;
}

function inferCarrier(trackingNumber: string | null, body: string, sender: string): string | null {
  const lowerBody = body.toLowerCase();
  const lowerSender = sender.toLowerCase();

  if (trackingNumber) {
    if (trackingNumber.startsWith('1Z')) return 'UPS';
    if (/^94/.test(trackingNumber)) return 'FedEx';
    if (/^EA/i.test(trackingNumber)) return 'DHL';
    if (/^[A-Z]{2}[0-9]{9}[A-Z]{2}$/.test(trackingNumber)) return 'Royal Mail';
    if (/^[0-9]{12,22}$/.test(trackingNumber)) return 'Generic';
  }

  if (lowerBody.includes('ups') || lowerSender.includes('ups')) return 'UPS';
  if (lowerBody.includes('fedex') || lowerSender.includes('fedex')) return 'FedEx';
  if (lowerBody.includes('dhl') || lowerSender.includes('dhl')) return 'DHL';
  if (lowerBody.includes('usps') || lowerSender.includes('usps')) return 'USPS';
  if (lowerBody.includes('royal mail') || lowerSender.includes('royalmail')) return 'Royal Mail';

  return null;
}

interface AmountResult { amount: number | null; currency: string }

/**
 * Extract the order total from the body. Strategy in priority order:
 *   1. Anchored "(grand|order|sub)? total[: ]" + amount — the most
 *      reliable signal. Picks the LAST anchored match (some emails
 *      list "subtotal" first then "total" later).
 *   2. Largest currency-amount in the body. Order totals are almost
 *      always the largest number on the page (line items < total).
 *   3. First currency-amount as a last resort (legacy behavior).
 *
 * Previously the function returned the FIRST currency-amount it found,
 * which is usually a single line item, not the order total. Multiple
 * merchants (Vulkit, Body&Fit, Matador) were storing the wrong number.
 */
function extractTotal(body: string): AmountResult {
  // Currency tokens we recognize, mapped to a canonical 3-letter code.
  const currencySymbol: Record<string, string> = {
    '€': 'EUR', '£': 'GBP', '$': 'USD',
    'eur': 'EUR', 'gbp': 'GBP', 'usd': 'USD',
  };

  // Match an amount + currency in either "$12.34" or "12,34 EUR" shape.
  // Capture: 1=symbol-or-code, 2=number-when-symbol-prefixed, 3=number-suffix-currency
  const amountRe = /(?:([€£$])\s*([0-9]{1,5}(?:[.,\s][0-9]{3})*(?:[.,][0-9]{2})?)|([0-9]{1,5}(?:[.,\s][0-9]{3})*(?:[.,][0-9]{2})?)\s*(EUR|GBP|USD)\b)/gi;

  function parseAmount(numStr: string): number | null {
    // Handle European thousand separators: "1.234,56" or "1 234,56"
    let normalized = numStr.replace(/\s/g, '');
    const lastComma = normalized.lastIndexOf(',');
    const lastDot = normalized.lastIndexOf('.');
    if (lastComma > lastDot) {
      // Comma is the decimal separator — strip dots, swap comma for dot
      normalized = normalized.replace(/\./g, '').replace(',', '.');
    } else if (lastDot > lastComma) {
      // Dot is the decimal separator — strip commas
      normalized = normalized.replace(/,/g, '');
    }
    const n = parseFloat(normalized);
    return !isNaN(n) && n > 0 ? n : null;
  }

  // Collect every (amount, currency) pair in the body.
  const matches: Array<{ amount: number; currency: string; index: number }> = [];
  let m: RegExpExecArray | null;
  while ((m = amountRe.exec(body)) !== null) {
    const sym = (m[1] || m[4] || '').toLowerCase();
    const num = m[2] || m[3] || '';
    const amount = parseAmount(num);
    if (amount === null) continue;
    const currency = currencySymbol[sym] || 'USD';
    matches.push({ amount, currency, index: m.index });
  }
  if (matches.length === 0) return { amount: null, currency: 'USD' };

  // Strategy 1: anchored-total — find the rightmost "Total..." label and
  // pick the next amount within ~120 chars after it.
  const anchorRe = /(?:grand\s+total|order\s+total|total\s+(?:price|amount|due|paid)|^total\b|\btotal\b)\s*[:\s]*/gi;
  let lastAnchor = -1;
  let am: RegExpExecArray | null;
  while ((am = anchorRe.exec(body)) !== null) {
    // Skip "subtotal" — we want the FINAL total. anchorRe doesn't match
    // "subtotal" because of `\btotal\b`, but be defensive.
    const before = body.slice(Math.max(0, am.index - 4), am.index).toLowerCase();
    if (before.endsWith('sub')) continue;
    lastAnchor = am.index + am[0].length;
  }
  if (lastAnchor >= 0) {
    const after = matches.find(x => x.index >= lastAnchor && x.index < lastAnchor + 120);
    if (after) return { amount: after.amount, currency: after.currency };
  }

  // Strategy 2: largest amount in the body. Heuristic but very reliable
  // since totals beat line items in practice.
  const largest = matches.reduce((a, b) => (b.amount > a.amount ? b : a));
  return { amount: largest.amount, currency: largest.currency };
}

function extractOrderDate(body: string): Date | null {
  const patterns = [
    /(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})/,
    /(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})/,
    /([A-Za-z]{3,})\s+(\d{1,2}),?\s+(\d{4})/,
  ];

  for (const pattern of patterns) {
    const m = body.match(pattern);
    if (m) {
      try {
        const d = new Date(m[0]);
        if (!isNaN(d.getTime()) && d.getFullYear() >= 2020) {
          return d;
        }
      } catch {}
    }
  }

  return null;
}

function extractShippedDate(body: string): Date | null {
  return extractOrderDate(body); // Same pattern works for shipped date
}
