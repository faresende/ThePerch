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
 * Optional metadata the listener can pass alongside subject/body/sender.
 * `senderName` comes from the `From:` display name and is the cleanest
 * source of merchant identity. `folders` is the list of mailbox / label
 * names — used as a soft signal (e.g. "Paper Trail" tilts toward
 * purchase, "Newsletters" away from it).
 *
 * `hasLearnedSender` — pre-fetched flag from the `learned_senders` table.
 * The orders-autopilot looks up the sender BEFORE calling classifyEmail
 * and passes true here when a row matches. A learned sender is one the
 * user has explicitly resolved in the iOS review queue; future emails
 * from the same address only need a moderate purchase signal (instead
 * of the normal 0.8 threshold) to be classified as purchase. This lets
 * the system pick up obvious-but-non-keyword purchase emails without
 * requeueing the same merchant.
 */
export interface ClassifyMeta {
  senderName?: string;
  folders?: string[];
  hasLearnedSender?: boolean;
}

/**
 * Classifies an email body as purchase or shipping type.
 */
export function classifyEmail(
  subject: string,
  body: string,
  senderEmail: string,
  meta: ClassifyMeta = {},
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

  // Folder soft-signal: emails routed to a "receipts" / "paper trail" /
  // "shopping" folder by the user's mail rules are very likely to be
  // commerce. A user-defined sort is a stronger signal than any keyword.
  // Tilts but doesn't gate (false positives still need to clear keyword
  // threshold). Accent-insensitive substring match.
  const folderHints = (meta.folders ?? []).map(f => f.toLowerCase());
  const inCommerceFolder = folderHints.some(f =>
    /paper.?trail|receipts?|shopping|orders?|purchases?|invoices?/i.test(f),
  );
  if (inCommerceFolder) {
    signals.purchaseScore += 0.5;
    signals.isPurchase = signals.purchaseScore >= 0.8;
    signals.matchedKeywords.push('folder:commerce');
  }
  // Newsletters folder = strong negative signal.
  if (folderHints.some(f => /newsletter|promo|marketing/i.test(f))) {
    signals.purchaseScore = Math.max(0, signals.purchaseScore - 0.4);
    signals.isPurchase = signals.purchaseScore >= 0.8;
  }

  // Learned-sender boost: if the user has previously resolved a review
  // item for this sender, a moderate purchase signal is enough to
  // classify as purchase. We don't unconditionally call it commerce
  // (newsletters from a known merchant should still skip), but we lower
  // the gate so weird-phrasing order emails ("Final reminder", "Payment
  // received for #X") still land in orders. Threshold is 0.4 so at
  // least one real purchase keyword has to fire.
  if (meta.hasLearnedSender && signals.purchaseScore >= 0.4) {
    signals.isPurchase = true;
    signals.matchedKeywords.push('learned_sender');
  }

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

  // Travel-reminder counter-signals. Trip itineraries, hotel "review your
  // upcoming reservation", airline check-in nudges, etc. are textually
  // close to purchase confirmations — they have totals, confirmation
  // numbers, "non-refundable purchase" boilerplate — but they are NOT
  // orders we want to track. Subtract aggressively: a strong travel
  // signal pulls the score below the 0.8 purchase threshold even when
  // a few purchase keywords incidentally hit. Caught by hand: an Amex
  // travel reminder ("FABIO, review details for your upcoming trip")
  // landing as a $550 American Express order.
  const travelReminderSignals: Array<{ keyword: string; weight: number }> = [
    { keyword: 'upcoming trip', weight: 0.7 },
    { keyword: 'your trip', weight: 0.4 },
    { keyword: 'review details for your', weight: 0.7 },
    { keyword: 'review your reservation', weight: 0.7 },
    { keyword: 'before your departure', weight: 0.7 },
    { keyword: 'before your trip', weight: 0.7 },
    { keyword: 'before your stay', weight: 0.7 },
    { keyword: 'your itinerary', weight: 0.7 },
    { keyword: 'itinerary', weight: 0.4 },
    { keyword: 'view your reservation', weight: 0.6 },
    { keyword: 'manage your booking', weight: 0.6 },
    { keyword: 'manage your reservation', weight: 0.6 },
    { keyword: 'hotel confirmation', weight: 0.5 },
    { keyword: 'check-in starts', weight: 0.6 },
    { keyword: 'check in:', weight: 0.4 },
    { keyword: 'check-in:', weight: 0.4 },
    { keyword: 'flight is not confirmed', weight: 0.6 },
    { keyword: 'reservation/purchase', weight: 0.5 },
    { keyword: 'cancellation policy', weight: 0.3 },
  ];

  let travelReminderScore = 0;
  for (const signal of travelReminderSignals) {
    if (text.includes(signal.keyword)) {
      travelReminderScore += signal.weight;
      matchedKeywords.push(`travel:${signal.keyword}`);
    }
  }

  // If travel signal is strong, demote purchase. >=1.0 is a clear trip
  // reminder — gut the purchase score so it lands in "other". 0.5–1.0 is
  // ambiguous (could be a real travel purchase confirmation), so apply a
  // partial penalty.
  if (travelReminderScore >= 1.0) {
    purchaseScore = Math.max(0, purchaseScore - 1.5);
  } else if (travelReminderScore >= 0.5) {
    purchaseScore = Math.max(0, purchaseScore - 0.5);
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
 *
 * `learnedMerchantName` is an optional pre-resolved merchant name from
 * the `learned_senders` table (Tier 3). When provided, it wins over
 * every other inference path — the user explicitly taught us this
 * mapping, so we never second-guess it.
 */
export function extractOrderFields(
  subject: string,
  body: string,
  senderEmail: string,
  emailId: string,
  displayName?: string,
  learnedMerchantName?: string,
): {
  merchantName: string;
  merchantSource: MerchantSource;
  normalizedMerchant: string;
  orderNumber: string | null;
  orderDate: Date | null;
  totalAmount: number | null;
  currency: string;
  confidence: number;
} {
  const signals = analyzeSignals(`${subject} ${body}`.toLowerCase(), senderEmail.toLowerCase());

  // Merchant resolution. Source is exposed so the caller can decide
  // whether to invoke an LLM second-pass (only worth it for the weak
  // `domainStem` last-resort branch).
  const inferred = inferMerchantNameInner(senderEmail, subject, body, displayName, learnedMerchantName);
  const merchantName = inferred.name
    || prettifyDomain(senderEmail.split('@')[1]?.replace(/^www\./, '').split('.')[0] || 'Unknown');
  const merchantSource = inferred.source ?? 'domainStem';

  // Extract order number
  const orderNumber = extractOrderNumber(subject, body);

  // Extract total amount
  const { amount, currency } = extractTotal(body);

  // Extract order date
  const orderDate = extractOrderDate(body) || new Date();

  return {
    merchantName,
    merchantSource,
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

/**
 * Strip generic suffixes from a display name to recover the merchant.
 *   "Body&Fit Customer Service" -> "Body&Fit"
 *   "Hardgraft Members Club" -> "Hardgraft"
 *   "Apple Receipts" -> "Apple"
 *   "Vulkit Support" -> "Vulkit"
 * Returns null if the cleaned name is empty or generic-only.
 */
function cleanDisplayName(name: string): string | null {
  if (!name) return null;
  // Strip parens / quotes wrapping
  let s = name.replace(/["“”']/g, '').trim();
  // Strip trailing email-suffix-style noise: "[via Shopify]", "(do not reply)"
  s = s.replace(/\s*\[[^\]]*\]\s*$/g, '').replace(/\s*\([^)]*\)\s*$/g, '').trim();

  // Strip generic role suffixes (case-insensitive). Keep removing until
  // none match — "Body&Fit Customer Service Team" should drop both.
  const suffixes = [
    'customer service', 'customer care', 'customer support',
    'support team', 'support', 'sales team', 'sales',
    'orders', 'order team', 'order desk',
    'shop', 'store', 'shipping', 'shipping team',
    'newsletter', 'marketing', 'team', 'members club',
    'receipts', 'receipt', 'help', 'noreply', 'no reply',
    'no-reply', 'do not reply', 'donotreply',
    'autoreply', 'mailer', 'notifications?', 'updates?',
  ];
  let changed = true;
  while (changed) {
    changed = false;
    for (const suffix of suffixes) {
      const re = new RegExp(`[\\s,\\-—|]+${suffix}\\s*$`, 'i');
      if (re.test(s)) {
        s = s.replace(re, '').trim();
        changed = true;
      }
    }
  }

  // Reject pure-generic results. If the name is just "noreply" / "team"
  // / "do not reply" itself we can't trust it.
  const lower = s.toLowerCase();
  const genericOnly = new Set([
    '', 'noreply', 'no reply', 'no-reply', 'donotreply', 'do not reply',
    'team', 'support', 'orders', 'order', 'sales', 'shop', 'store',
    'newsletter', 'mailer', 'autoreply', 'notification', 'notifications',
  ]);
  if (genericOnly.has(lower)) return null;
  return s;
}

/**
 * Pretty-print a domain stem into a plausible merchant name when no
 * better source is available. Heuristic — not always right, but better
 * than the bare lowercase domain.
 *   "bodyandfit" -> "Body & Fit"
 *   "mrporter"   -> "MR PORTER" (special-cased common pattern)
 *   "apple"      -> "Apple"
 *   "jacquesmariemage" -> "Jacquesmariemage" (untouched — too dense)
 */
function prettifyDomain(stem: string): string {
  if (!stem) return stem;
  let s = stem.toLowerCase();
  // Common compound separators: "and", "the", "of", "for". Insert spaces.
  s = s.replace(/(.)(and|the|of|for)(.)/gi, '$1 $2 $3');
  // Title-case each word.
  s = s.replace(/(^|\s)(\w)/g, (_m, sp, c) => sp + c.toUpperCase());
  // "& and" → "&"; "And" between two words → "&" (visual cleanliness)
  s = s.replace(/\bAnd\b/g, '&');
  return s;
}

/**
 * Source of the merchant name. Used by callers to decide whether to
 * trust the regex result or invoke an LLM second pass.
 *   `learnedSender` — user resolved a review_item with this sender→merchant
 *                     mapping. Highest-trust source — never overridden.
 *   `known`        — sender matched the hardcoded known-merchants list.
 *                    Trustworthy.
 *   `displayName`  — pulled from the From: header display name.
 *                    Trustworthy.
 *   `shopifyBody`  — Shopify-routed sender; recovered from body.
 *                    Trustworthy when matched.
 *   `subject`      — extracted from subject heuristic. OK.
 *   `domainStem`   — last-resort prettify of the sender domain.
 *                    Weakest — LLM can override.
 *   `null`         — couldn't infer.
 */
export type MerchantSource =
  | 'learnedSender'
  | 'known'
  | 'displayName'
  | 'shopifyBody'
  | 'subject'
  | 'domainStem'
  | null;

export function inferMerchantNameWithSource(
  sender: string,
  subject: string,
  body: string,
  displayName?: string,
  learnedMerchantName?: string,
): { name: string | null; source: MerchantSource } {
  const result = inferMerchantNameInner(sender, subject, body, displayName, learnedMerchantName);
  return result;
}

function inferMerchantNameInner(
  sender: string,
  subject: string,
  body: string,
  displayName?: string,
  learnedMerchantName?: string,
): { name: string | null; source: MerchantSource } {
  // -1. Learned-sender table wins over everything else. The user has
  //     explicitly resolved a review item with this mapping; we never
  //     override it with hardcoded lists, display names, body recovery,
  //     or LLM output.
  if (learnedMerchantName && learnedMerchantName.trim()) {
    return { name: learnedMerchantName.trim(), source: 'learnedSender' };
  }
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

  // Canonicalize an arbitrary candidate string against the known list by
  // alphanum-normalizing both sides and looking for a substring match.
  // This catches "Matador Equipment EU" → "Matador" (display name has
  // spaces; the known key is "matadorequipment") and "VULKIT" → "Vulkit"
  // (case difference). Returns the canonical merchant name on hit.
  const canonicalFromKnown = (candidate: string): string | null => {
    const norm = candidate.toLowerCase().replace(/[^a-z0-9]/g, '');
    if (!norm) return null;
    for (const [k, v] of Object.entries(known)) {
      if (norm.includes(k)) return v;
    }
    return null;
  };

  // 0. Known-merchant boost wins outright when sender matches.
  for (const [domain, name] of Object.entries(known)) {
    if (lower.includes(domain)) return { name, source: 'known' };
  }

  // 1. Display name from the From: header is usually the cleanest source.
  //    Strip generic suffixes ("Customer Service", "Team", etc), then try
  //    to promote it to 'known' canonical form before falling back to the
  //    raw cleaned string. This is what catches "Matador Equipment EU" →
  //    "Matador" — the sender domain (`store+...@t.shopifyemail.com`)
  //    can't match the hardcoded list, but the display name does.
  if (displayName) {
    const cleaned = cleanDisplayName(displayName);
    if (cleaned) {
      const canon = canonicalFromKnown(cleaned);
      if (canon) return { name: canon, source: 'known' };
      return { name: cleaned, source: 'displayName' };
    }
  }

  // 2. Shopify-routed senders (`store+xyz@t.shopifyemail.com`) hide the
  //    real merchant from the sender field. Recover from the body in 3
  //    ways (cheapest to most heuristic). Body match is normalized so
  //    multi-word brand mentions like "Matador Equipment" still hit a
  //    "matadorequipment" key.
  if (lower.includes('shopifyemail')) {
    const bodyNorm = body.toLowerCase().replace(/[^a-z0-9]/g, '');
    for (const [domain, name] of Object.entries(known)) {
      if (bodyNorm.includes(domain)) return { name, source: 'known' };
    }
    const phraseMatch = body.match(
      /(?:thank you for your (?:purchase|order)!?\s*\*+\s*\n*\s*|from\s+)([A-Z][A-Za-z0-9][A-Za-z0-9 &.'-]{2,30})/,
    );
    if (phraseMatch) {
      const cand = phraseMatch[1].trim();
      const canon = canonicalFromKnown(cand);
      if (canon) return { name: canon, source: 'known' };
      return { name: cand, source: 'shopifyBody' };
    }
    const headerMatch = body.match(/<title>([^<]+)<\/title>/i);
    if (headerMatch) {
      const cleaned = headerMatch[1].replace(/^order\s+#?\S+\s*[\-:|]\s*/i, '').trim();
      if (cleaned && !/^order/i.test(cleaned)) {
        const canon = canonicalFromKnown(cleaned);
        if (canon) return { name: canon, source: 'known' };
        return { name: cleaned, source: 'shopifyBody' };
      }
    }
  }

  // 3. Subject extraction (rejecting junk leads).
  const subjectMatch = subject.match(/^([A-Za-z][A-Za-z\s&'-]+?)\s/);
  if (subjectMatch) {
    const candidate = subjectMatch[1].trim();
    const lowerCand = candidate.toLowerCase();
    const junkLeads = new Set([
      'your', 'order', 'thank', 'thanks', 'we', 'a', 'the', 'hi', 'hello',
      'welcome', 'confirmation', 'receipt', 'payment',
    ]);
    if (!junkLeads.has(lowerCand)) return { name: candidate, source: 'subject' };
  }

  // 4. Last resort: pretty-print the sender domain stem.
  const domainStem = sender.split('@')[1]?.replace(/^www\./, '').split('.')[0];
  if (domainStem && domainStem.length > 1) {
    return { name: prettifyDomain(domainStem), source: 'domainStem' };
  }

  return { name: null, source: null };
}

/** Backward-compat wrapper: returns just the name. */
function inferMerchantName(sender: string, subject: string, body: string, displayName?: string): string | null {
  return inferMerchantNameInner(sender, subject, body, displayName).name;
}

function normalizeMerchant(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '')
    .trim();
}

function extractOrderNumber(subject: string, body: string): string | null {
  // Strip obvious HTML noise before regex so we don't match things like
  // cellpadding="0", style="..." attribute values, or — worst-offender —
  // entire <style>...</style> blocks containing CSS selectors like
  // `#outlook a { padding: 0; }` that would otherwise feed `#OUTLOOK`
  // straight into the `#([A-Z]{2,}...)` order-number pattern.
  // Order matters: drop full <style>/<script> blocks BEFORE the generic
  // tag stripper, otherwise their inner text leaks through.
  const strip = (s: string) =>
    s
      .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
      .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, ' ')
      .replace(/<!--\[if[^\]]*\]>[\s\S]*?<!\[endif\]-->/gi, ' ')
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
  // attributes, well-known CSS hooks (`#outlook a {...}`, `#yiv...`),
  // mailer keywords, and pure 3/6/8-char hex colors that slip through
  // `#XYZ` patterns.
  const isHtmlJunk = (v: string) =>
    /^(CELLPADDING|CELLSPACING|BGCOLOR|BORDER|ALIGN|VALIGN|WIDTH|HEIGHT|FONT|COLOR|STYLE|CLASS|UTF|HTML|BODY|TABLE|DIV|SPAN|HEADER|FOOTER|OUTLOOK|YIV|MSO|GMAIL|XMLNS|DOCTYPE)$/.test(v) ||
    /^YIV[0-9]+$/.test(v) ||
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
