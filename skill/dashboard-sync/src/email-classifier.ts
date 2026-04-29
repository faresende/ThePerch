/**
 * email-classifier.ts
 * Classifies emails as purchase_confirmation vs shipping_notification vs other.
 * Uses keyword + signal analysis for classification.
 */

import {
  extractTrackingCandidates,
  pickWinner,
  TrackingCandidate,
} from './tracking-candidates';
import { extractETACandidates, ETACandidate } from './extract-eta';

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
 * Carriers — postal services + couriers + tracking aggregators. An email
 * from any of these is a SHIPPING NOTIFICATION by definition, never a
 * fresh purchase confirmation, regardless of how many "your purchase"
 * phrases appear in the body. Caught in the wild: a Correos email about
 * an Amazon shipment landing as a $null "Correos" order.
 *
 * When the sender matches one of these, the classifier short-circuits
 * to `shipping_notification` and the autopilot recovers the actual
 * merchant from the body via the known-merchant list (so the shipment
 * gets linked to e.g. the user's existing Amazon order, not stored
 * under "Correos").
 */
const CARRIER_SENDERS: string[] = [
  'correos',          // Spain / Portugal post
  'ctt.pt',           // Portugal post (CTT)
  'dhl.',             // DHL (matches dhl.com, dhl.de, etc.)
  'ups.com',          // UPS
  'fedex.com',        // FedEx
  'usps.com',         // USPS
  'royalmail.com',    // Royal Mail
  'postnl.nl',        // PostNL
  'post.nl',          // PostNL alt
  'gls-group.eu',     // GLS
  'dpd.com',          // DPD
  'dpd.de',           // DPD DE
  'gls-pakket',       // GLS pakket
  'colissimo',        // Colissimo (FR)
  'laposte.fr',       // La Poste FR
  'mondialrelay',     // Mondial Relay
  'inpost',           // InPost
  'chronopost',       // Chronopost
  'tnt.com',          // TNT
  '17track',          // Aggregator
  'aftership',        // Aggregator
  'parcelsapp',       // Aggregator
  'route.com',        // Tracking aggregator
];

function isCarrierSender(senderEmail: string): boolean {
  const s = senderEmail.toLowerCase();
  return CARRIER_SENDERS.some(pat => s.includes(pat));
}

/**
 * Public test for "is the sender a carrier?". Exposed so the
 * orders-autopilot's shipping-notification handler can branch on this
 * to recover the actual merchant from the body instead of trusting
 * the sender's display name (which would yield "Correos" / "DHL" etc.).
 */
export function senderIsCarrier(senderEmail: string): boolean {
  return isCarrierSender(senderEmail);
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
 * Result of `classifyEmail`. Beyond the headline `type` + `confidence`,
 * this exposes the underlying purchase/shipping scores and the matched
 * keywords so the caller can write rich telemetry without having to
 * re-run the analyzer.
 */
export interface ClassifyResult {
  type: EmailType;
  confidence: number;
  purchaseScore: number;
  shippingScore: number;
  matchedKeywords: string[];
}

/**
 * Classifies an email body as purchase or shipping type.
 */
export function classifyEmail(
  subject: string,
  body: string,
  senderEmail: string,
  meta: ClassifyMeta = {},
): ClassifyResult {
  if (isNonGoodsSender(senderEmail)) {
    return {
      type: 'other',
      confidence: 1,
      purchaseScore: 0,
      shippingScore: 0,
      matchedKeywords: ['non_goods_sender'],
    };
  }
  // Carriers always produce shipping notifications, never purchase
  // confirmations, even when their body parrots "thanks for your
  // purchase" boilerplate. Short-circuit before keyword scoring runs.
  if (isCarrierSender(senderEmail)) {
    return {
      type: 'shipping_notification',
      confidence: 0.95,
      purchaseScore: 0,
      shippingScore: 0.95,
      matchedKeywords: ['carrier_sender'],
    };
  }
  const lowerSender = senderEmail.toLowerCase();

  // Subject takes priority: a clear "order ... confirmed" / "thanks for
  // your order" in the subject means PURCHASE confirmation regardless of
  // what's in the body. This catches cases like Demo Merchant where the
  // order-confirmation email also embeds a tracking number — body
  // shipping signals would otherwise win and route to shipping.
  //
  // BUT — protect the fastpath against subjects that also carry strong
  // shipping cues. Subjects like "A shipment from order #X is on the
  // way" hit BOTH purchase ("order #") and shipping ("shipment from
  // order", "is on the way") signals; the fastpath would have picked
  // purchase and silently skipped the shipping pipeline. Now the
  // fastpath only fires when shipping is meaningfully quieter than
  // purchase in the subject.
  const subjectSignals = analyzeSignals(subject.toLowerCase(), lowerSender);
  const subjectShippingDominant = subjectSignals.shippingScore >= 0.7
    && subjectSignals.shippingScore >= subjectSignals.purchaseScore - 0.2;
  if (
    subjectSignals.isPurchase
    && subjectSignals.purchaseScore >= 0.85
    && !subjectShippingDominant
  ) {
    return {
      type: 'purchase_confirmation',
      confidence: Math.min(subjectSignals.confidence, 1),
      purchaseScore: subjectSignals.purchaseScore,
      shippingScore: subjectSignals.shippingScore,
      matchedKeywords: [...subjectSignals.matchedKeywords, 'subject_only_fastpath'],
    };
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

  // Common diagnostic fields shared by every return path below.
  const diag = {
    purchaseScore: signals.purchaseScore,
    shippingScore: signals.shippingScore,
    matchedKeywords: signals.matchedKeywords,
  };

  if (signals.isPurchase && signals.isShipping) {
    // Both signals — compare RAW summed scores so ties are rare. Order
    // confirmations from real merchants almost always carry some shipping
    // language too (tracking, delivery date, carrier hint). Without
    // numeric scoring those tie at 1-vs-1 and the email gets dumped to
    // "other", which silently drops orders. Using the raw sums lets
    // "Order #X confirmed" beat "tracking number TBD" cleanly.
    if (signals.purchaseScore > signals.shippingScore) {
      return { type: 'purchase_confirmation', confidence: signals.confidence, ...diag };
    } else if (signals.shippingScore > signals.purchaseScore) {
      return { type: 'shipping_notification', confidence: signals.confidence, ...diag };
    }
    // Genuine tie — prefer purchase since shipping notifications without
    // a clear purchase signal are rare. Better to land in orders and let
    // the extractor demote to review_item than to silently skip.
    return { type: 'purchase_confirmation', confidence: signals.confidence * 0.6, ...diag };
  }

  if (signals.isPurchase) {
    return { type: 'purchase_confirmation', confidence: signals.confidence, ...diag };
  }

  if (signals.isShipping) {
    return { type: 'shipping_notification', confidence: signals.confidence, ...diag };
  }

  return { type: 'other', confidence: signals.confidence, ...diag };
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

    // ─── Portuguese (PT/BR) ────────────────────────────────────────────
    { keyword: 'pedido confirmado', weight: 0.9 },
    { keyword: 'pedido recebido', weight: 0.85 },
    { keyword: 'recebemos o seu pedido', weight: 0.85 },
    { keyword: 'recebemos seu pedido', weight: 0.85 },
    { keyword: 'obrigado pelo seu pedido', weight: 0.9 },
    { keyword: 'obrigado pela sua compra', weight: 0.9 },
    { keyword: 'confirmação do pedido', weight: 0.85 },
    { keyword: 'confirmação de pedido', weight: 0.85 },
    { keyword: 'confirmação da encomenda', weight: 0.85 },
    { keyword: 'a sua encomenda', weight: 0.7 },
    { keyword: 'sua encomenda', weight: 0.7 },
    { keyword: 'número do pedido', weight: 0.8 },
    { keyword: 'número da encomenda', weight: 0.8 },
    { keyword: 'pedido nº', weight: 0.8 },
    { keyword: 'encomenda nº', weight: 0.8 },
    { keyword: 'pagamento confirmado', weight: 0.8 },

    // ─── Spanish (ES) ──────────────────────────────────────────────────
    { keyword: 'pedido confirmado', weight: 0.9 }, // also PT
    { keyword: 'gracias por su pedido', weight: 0.9 },
    { keyword: 'gracias por tu pedido', weight: 0.9 },
    { keyword: 'gracias por su compra', weight: 0.9 },
    { keyword: 'gracias por tu compra', weight: 0.9 },
    { keyword: 'confirmación de pedido', weight: 0.85 }, // also PT
    { keyword: 'confirmación de su pedido', weight: 0.85 },
    { keyword: 'su pedido', weight: 0.6 },
    { keyword: 'tu pedido', weight: 0.6 },
    { keyword: 'número de pedido', weight: 0.8 },
    { keyword: 'hemos recibido su pedido', weight: 0.85 },
    { keyword: 'hemos recibido tu pedido', weight: 0.85 },
    { keyword: 'pago confirmado', weight: 0.8 },

    // ─── French (FR) ───────────────────────────────────────────────────
    { keyword: 'commande confirmée', weight: 0.9 },
    { keyword: 'merci pour votre commande', weight: 0.9 },
    { keyword: 'merci pour votre achat', weight: 0.9 },
    { keyword: 'confirmation de commande', weight: 0.85 },
    { keyword: 'confirmation de votre commande', weight: 0.85 },
    { keyword: 'votre commande', weight: 0.6 },
    { keyword: 'numéro de commande', weight: 0.8 },
    { keyword: 'commande n°', weight: 0.8 },
    { keyword: 'nous avons bien reçu votre commande', weight: 0.85 },
    { keyword: 'paiement confirmé', weight: 0.8 },

    // ─── German (DE) ───────────────────────────────────────────────────
    { keyword: 'bestellung bestätigt', weight: 0.9 },
    { keyword: 'bestellbestätigung', weight: 0.9 },
    { keyword: 'vielen dank für ihre bestellung', weight: 0.9 },
    { keyword: 'vielen dank für deine bestellung', weight: 0.9 },
    { keyword: 'ihre bestellung', weight: 0.6 },
    { keyword: 'deine bestellung', weight: 0.6 },
    { keyword: 'bestellnummer', weight: 0.8 },
    { keyword: 'wir haben ihre bestellung erhalten', weight: 0.85 },
    { keyword: 'zahlung bestätigt', weight: 0.8 },

    // ─── Dutch (NL) — DemoOutdoors speaks Dutch ───────────────────────────
    { keyword: 'bestelling bevestigd', weight: 0.9 },
    { keyword: 'orderbevestiging', weight: 0.9 },
    { keyword: 'bedankt voor je bestelling', weight: 0.9 },
    { keyword: 'bedankt voor uw bestelling', weight: 0.9 },
    { keyword: 'je bestelling', weight: 0.6 },
    { keyword: 'uw bestelling', weight: 0.6 },
    { keyword: 'bestelnummer', weight: 0.8 },
    { keyword: 'we hebben je bestelling ontvangen', weight: 0.85 },
    { keyword: 'we hebben uw bestelling ontvangen', weight: 0.85 },
    { keyword: 'betaling bevestigd', weight: 0.8 },
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
    // Phrases that strongly imply "this email is reporting an
    // already-shipped package", even when they co-occur with order
    // numbers. Caught after Jacques Marie Mage + Vulkit shipping
    // emails were misclassified as purchase confirmations because
    // "order #X" (0.8 purchase weight) outscored everything else
    // and triggered the subject fastpath. These keywords give the
    // classifier enough shipping signal to defeat the fastpath.
    { keyword: 'shipment from order', weight: 1.0 },   // unambiguous: this IS a shipment email
    { keyword: 'is on the way', weight: 0.9 },
    { keyword: 'is on its way', weight: 0.9 },
    { keyword: 'on its way', weight: 0.7 },
    { keyword: 'on the way', weight: 0.7 },
    { keyword: 'has shipped', weight: 0.9 },
    { keyword: 'has been shipped', weight: 0.9 },
    { keyword: 'shipment', weight: 0.6 },              // bare noun — moderate
    // Multilingual variants for shipping cues. Match the same locale
    // coverage as the purchase keyword bank above.
    { keyword: 'a caminho', weight: 0.85 },            // PT — "on the way"
    { keyword: 'enviado', weight: 0.7 },               // PT/ES
    { keyword: 'envío', weight: 0.6 },                 // ES
    { keyword: 'expédié', weight: 0.85 },              // FR
    { keyword: 'en route', weight: 0.7 },              // FR
    { keyword: 'versandt', weight: 0.85 },             // DE
    { keyword: 'unterwegs', weight: 0.7 },             // DE — "on the way"
    { keyword: 'verzonden', weight: 0.85 },            // NL
    { keyword: 'onderweg', weight: 0.7 },              // NL
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
    // Apparel + EDC merchants the user orders from regularly
    'demo-merchant': 'Demo Merchant',
    'jacquesmariemage': 'Jacques Marie Mage',
    'vulkit': 'Vulkit',
    'demo-outdoors': 'DemoOutdoors',
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
  // (and PT/ES/FR/DE/NL equivalents) that the literal-keyword list misses.
  // Real-world subject lines like
  //   "Order #DEMO-108984 confirmed"
  //   "demo-merchant order HGMC-DEMO-0001 confirmed"
  //   "Your DemoOutdoors order is confirmed!"
  //   "Pedido #1234 confirmado"
  //   "Commande N°1234 confirmée"
  //   "Bestellung #1234 bestätigt"
  // all read as orders to a human but skip the literal phrasings. Single
  // fire so we don't double-count.
  const confirmedRegexes: RegExp[] = [
    // English: "order ... confirmed"
    /order(?:\s+[#a-z0-9-]{2,30}){0,3}\s+(?:is\s+|has\s+been\s+)?confirmed/i,
    // PT/ES: "pedido ... confirmado/a"; "encomenda ... confirmada"
    /(?:pedido|encomenda)(?:\s+[#a-z0-9ºn°-]{2,30}){0,3}\s+confirmad[oa]/i,
    // FR: "commande ... confirmée"
    /commande(?:\s+[#a-z0-9°n-]{2,30}){0,3}\s+confirm[ée]e?/i,
    // DE: "Bestellung ... bestätigt"
    /bestellung(?:\s+[#a-z0-9-]{2,30}){0,3}\s+best[äa]tigt/i,
    // NL: "bestelling ... bevestigd"
    /bestelling(?:\s+[#a-z0-9-]{2,30}){0,3}\s+bevestigd/i,
  ];
  if (!matchedKeywords.includes('order confirmed')) {
    for (const re of confirmedRegexes) {
      if (re.test(text)) {
        purchaseScore += 0.85;
        matchedKeywords.push('order_confirmed_regex');
        break; // only fire once
      }
    }
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

  // Marketing-email demotion. Real merchant emails OFTEN have marketing
  // CTAs in the footer ("Save 20% on your next order!", "back in stock") —
  // we can't naively count those as negative or we'll false-negative real
  // orders. Three layers of protection:
  //   1. Only count marketing signals from the subject + first 500 chars
  //      of body (footer CTAs in real order emails sit much later).
  //   2. A confident purchase signal makes the email immune — if the
  //      subject scored ≥0.85 OR the (post-travel) purchaseScore is
  //      ≥1.0, marketing demotion is skipped entirely.
  //   3. Otherwise, marketing score ≥0.5 in the early window applies a
  //      partial penalty; ≥1.0 applies a strong penalty.
  const marketingSignals: Array<{ keyword: string; weight: number }> = [
    { keyword: 'limited time', weight: 0.5 },
    { keyword: 'limited offer', weight: 0.5 },
    { keyword: 'use code', weight: 0.4 },
    { keyword: 'use promo code', weight: 0.5 },
    { keyword: 'save now', weight: 0.4 },
    { keyword: '% off', weight: 0.4 },
    { keyword: 'while supplies last', weight: 0.6 },
    { keyword: 'shop now', weight: 0.4 },
    { keyword: 'complete your purchase', weight: 0.5 },
    { keyword: 'back in stock', weight: 0.6 },
    { keyword: 'last chance', weight: 0.5 },
    { keyword: 'flash sale', weight: 0.6 },
    { keyword: 'new arrivals', weight: 0.4 },
    { keyword: 'recommended for you', weight: 0.4 },
  ];
  // Layer 1: only check the subject + early body window.
  const lowerText = text;  // already lowercased above
  const earlyWindow = lowerText.slice(0, 500); // text already starts with subject
  let marketingScore = 0;
  for (const signal of marketingSignals) {
    if (earlyWindow.includes(signal.keyword)) {
      marketingScore += signal.weight;
      matchedKeywords.push(`marketing:${signal.keyword}`);
    }
  }
  // Layer 2: high-confidence purchase signal makes the email immune.
  // (Subject was already scored above; we approximate "confident" via
  // the post-travel purchaseScore being ≥1.0.)
  const isConfidentPurchase = purchaseScore >= 1.0;
  // Layer 3: apply penalty proportional to marketing score, but only if
  // not already a confident purchase.
  if (!isConfidentPurchase) {
    if (marketingScore >= 1.0) {
      purchaseScore = Math.max(0, purchaseScore - 0.8);
    } else if (marketingScore >= 0.5) {
      purchaseScore = Math.max(0, purchaseScore - 0.3);
    }
  }

  // Confidence = the stronger of the two raw scores, capped at 1.0. The
  // earlier code was `Math.max(... , 1)` which FLOORED at 1 and then
  // capped at 1 — so every email returned confidence = 1.0 regardless
  // of whether any signal had matched. That made the orders-autopilot
  // `confidence >= 0.4 → fire LLM` gate fire on EVERY "other" email,
  // including Portuguese in-store receipts that have zero English
  // keywords (caught in the wild: an El Corte Inglés digital receipt
  // landing as a real order). Drop the bogus floor so confidence
  // tracks the actual signal strength.
  const confidence = Math.min(Math.max(purchaseScore, shippingScore), 1.0);

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
  /** Phase 1.5: full candidate list, ordered as discovered. Caller can
   *  feed into the parse-trace via `candidatesForTrace()`. Empty when
   *  no tracking number candidates exist. */
  trackingCandidates: TrackingCandidate[];
  /** Phase 1 ETA (2026-04-27): all extracted ETA candidates with
   *  source/rank. Caller picks the winner via `pickETA` and feeds the
   *  full list into parse_trace.eta_candidates. */
  etaCandidates: ETACandidate[];
} {
  const signals = analyzeSignals(`${subject} ${body}`.toLowerCase(), senderEmail.toLowerCase());

  // Phase 1.5: priority-rank-wins replaces first-match-wins. Enumerate
  // ALL plausible candidates with their source/rank, then pick the
  // highest-ranked. Carrier-owned URL > "Tracking number: X" body
  // pattern > isolated match > third-party redirect.
  const candidates = extractTrackingCandidates(subject, body, senderEmail);
  const winner = pickWinner(candidates);

  let trackingNumber: string | null = winner ? winner.number : null;
  let carrier: string | null = winner ? winner.carrier : null;

  // Fallback to legacy first-match if no candidates surfaced (e.g. an
  // email format we haven't taught the candidate extractor about yet).
  // Preserves prior behavior on the long tail.
  if (!trackingNumber) {
    trackingNumber = extractTrackingNumber(subject, body);
  }
  // Sender-domain-driven carrier inference still wins over candidate
  // carrier in the same way the legacy `inferCarrier` did — the sender
  // is authoritative if it's a carrier domain (correosexpress.com etc).
  carrier = inferCarrier(trackingNumber, body, senderEmail) ?? carrier;

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

  // Phase 1 ETA: extract carrier-email ETA candidates. Empty array
  // when no plausible delivery-date phrases are present (most
  // shipping notifications include one; some carrier emails don't).
  const etaCandidates = extractETACandidates(subject, body);

  return {
    trackingNumber,
    carrier,
    status,
    shippedAt,
    confidence: signals.confidence,
    trackingCandidates: candidates,
    etaCandidates,
  };
}

// ─── Helpers ────────────────────────────────────────────────────────────────

/**
 * Strip generic suffixes from a display name to recover the merchant.
 *   "DemoOutdoors Customer Service" -> "DemoOutdoors"
 *   "Demo Merchant Members Club" -> "Demo Merchant"
 *   "Apple Receipts" -> "Apple"
 *   "Vulkit Support" -> "Vulkit"
 * Returns null if the cleaned name is empty or generic-only.
 *
 * Exported for the jmap cross-reference path (orders-autopilot's
 * findSourceMerchantFromTracking calls it on the From: display name
 * of search-result emails).
 */
export function cleanDisplayName(name: string): string | null {
  if (!name) return null;
  // Strip parens / quotes wrapping
  let s = name.replace(/["“”']/g, '').trim();
  // Strip trailing email-suffix-style noise: "[via Shopify]", "(do not reply)"
  s = s.replace(/\s*\[[^\]]*\]\s*$/g, '').replace(/\s*\([^)]*\)\s*$/g, '').trim();

  // Strip generic role suffixes (case-insensitive). Keep removing until
  // none match — "DemoOutdoors Customer Service Team" should drop both.
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
 *   "demo-outdoors" -> "Demo Outdoors"
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

/**
 * Hardcoded sender-domain → canonical merchant-name list. Hoisted to
 * module scope so the body-recovery helper used by carrier-email
 * routing can reuse it without duplicating the data. Add a row here
 * whenever a new merchant ends up classified as "other" or stored
 * under a wrong name in the orders table.
 *
 * The canonicalFromKnown step uses these to normalise variant
 * spellings the LLM / display name might produce (e.g. "NOMOS Store"
 * + "NOMOS Glashütte" + "NOMOS" all collapsing to one canonical form).
 * Without canonicalisation a single merchant can produce 2–3 separate
 * orders rows for what's really the same purchase + its shipping
 * notification.
 */
const KNOWN_MERCHANTS: Record<string, string> = {
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
  // Apparel + EDC merchants the user orders from regularly
  'demo-merchant': 'Demo Merchant',
  'jacquesmariemage': 'Jacques Marie Mage',
  'vulkit': 'Vulkit',
  'demo-outdoors': 'DemoOutdoors',
  'matadorequipment': 'Matador',
  'matadorup': 'Matador',
  'vollebak': 'Vollebak',
  'mukama': 'Mukama',
  'lofree': 'Lofree',
  'nextsense': 'NextSense',
  'loveandtogether': 'Love&Together',
  'mrporter': 'MR PORTER',
  // Added 2026-04-26 after the FedEx/DPD cross-reference run
  // surfaced "NOMOS Store" / "NOMOS Glashütte" / "NOMOS" as separate
  // orders, and Aesop being canonicalised inconsistently.
  'nomos': 'NOMOS Glashütte',
  'nomosglashutte': 'NOMOS Glashütte',
  'nomosstore': 'NOMOS Glashütte',
  'aesop': 'Aesop',
};

/**
 * Recover a merchant name by scanning the email body for any of the
 * KNOWN_MERCHANTS keys. Used when the sender field is unhelpful (e.g.
 * a carrier email about an Amazon shipment — sender is Correos,
 * merchant we want is Amazon).
 *
 * Body is alphanum-normalized and lowercased before substring match,
 * so multi-word brand mentions ("Demo Outdoors", "Net-A-Porter") still
 * hit their compact key. Returns the first match (KNOWN_MERCHANTS
 * iteration order is insertion order).
 */
export function inferMerchantNameFromBody(body: string): string | null {
  const norm = body.toLowerCase().replace(/[^a-z0-9]/g, '');
  if (!norm) return null;
  for (const [key, name] of Object.entries(KNOWN_MERCHANTS)) {
    if (norm.includes(key)) return name;
  }
  return null;
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
  const known = KNOWN_MERCHANTS;

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

/**
 * Lowercase + alphanum-only merchant key used to dedupe orders across
 * shipping / re-classification passes. Accented characters are folded
 * to their ASCII base (ü → u, ç → c, é → e) BEFORE stripping non-
 * alphanumerics, so "NOMOS Glashütte" normalises to "nomosglashutte"
 * — same as a hypothetical "NOMOS Glashutte" without the umlaut.
 *
 * Without the NFD-fold step, the Unicode ü is treated as
 * non-alphanumeric and stripped entirely — caught in the wild as
 * "nomosglashtte" missing the U, which broke shipment-to-order
 * matching for the FedEx tracking on the Nomos order.
 *
 * Exported so orders-autopilot + OrdersService normalise identically;
 * any drift between callers re-creates the dupe-orders problem.
 */
export function normalizeMerchant(name: string): string {
  return name
    .normalize('NFD')                       // decompose: ü → u + combining-diaeresis
    .replace(/[̀-ͯ]/g, '')        // strip combining marks
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

  // Multilingual commerce-anchor words. Every viable order-number pattern
  // requires the token to follow one of these — that's the proximity rule.
  // Empirically (see backtest in commit history) the order number lives
  // either in the subject or within ~30 chars of an anchor in the body
  // 100% of the time across our test corpus; the previous standalone
  // `#XYZ` pattern was the source of every junk extraction we've ever
  // had (#OUTLOOK from CSS, #DADAD2 from hex colors, etc.).
  const ANCHOR = '(?:order|pedido|encomenda|orden|commande|bestellung|bestelling|ordine)';

  // Patterns in order of specificity. Each one ANCHORS to a commerce
  // word so the captured token is by construction near "order" /
  // "pedido" / "commande" / etc. — proximity is built in.
  const patterns: RegExp[] = [
    // "Order #AB-12345678" / "pedido #AB-12345678"
    new RegExp(`${ANCHOR}\\s*#\\s*([A-Z0-9][A-Z0-9-]{4,24})`, 'i'),
    // "order number: AB-12345678" / "número de pedido: X" / "numéro de commande: X"
    new RegExp(`(?:${ANCHOR}\\s+(?:number|nº|n°|no\\.?|numero|número)|(?:numero|número|num\\.|n[ºo°]\\.?)\\s+(?:de\\s+|do\\s+|da\\s+)?${ANCHOR})\\s*[:#]?\\s*([A-Z0-9][A-Z0-9-]{4,24})`, 'i'),
    // Amazon-style "order 123-1234567-1234567"
    new RegExp(`${ANCHOR}\\s+(\\d{3}-\\d{7}-\\d{7})`, 'i'),
    // "order HGMC-DEMO-0001" / "pedido ABC-12345" — bare token after the
    // anchor (no # required). Restricted to merchant-style prefixes
    // (≥2 letters, ≥1 digit somewhere) so we don't scoop "order details"
    // / "pedido confirmado" / "commande confirmée".
    new RegExp(`${ANCHOR}\\s+([A-Z]{2,}[A-Z0-9-]*[0-9][A-Z0-9-]*)`, 'i'),
    // "Order 1723 confirmed" / "Pedido 1723 confirmado" — pure-numeric
    // Shopify-style. Multilingual completion words.
    new RegExp(`${ANCHOR}\\s+(\\d{3,8})\\s+(?:confirmed|confirmad[oa]|confirm[ée]e?|best[äa]tigt|bevestigd)`, 'i'),
    // "thanks for your order BF-DEMO-0001" — token immediately after the
    // anchor in body prose. Matches DemoOutdoors-style emails.
    new RegExp(`(?:thanks?\\s+for\\s+your\\s+|obrigado\\s+pelo\\s+seu\\s+|gracias\\s+por\\s+(?:su|tu)\\s+|merci\\s+pour\\s+votre\\s+|vielen\\s+dank\\s+für\\s+(?:ihre|deine)\\s+|bedankt\\s+voor\\s+(?:je|uw)\\s+)${ANCHOR}\\s+([A-Z0-9][A-Z0-9-]{4,24})`, 'i'),
  ];

  // Tokens we should never accept as an order number — common HTML/CSS
  // attributes, well-known CSS hooks, mailer keywords, and 3/6/8-char
  // hex colors. Defense in depth — the proximity rule above already
  // rejects most of these by structure, but belt-and-suspenders.
  //
  // Important: a 6-char hex color check would otherwise false-reject
  // pure-digit Shopify order numbers like "DEMO-108984" / "DEMO-104383" (every
  // char is in 0-9 ⊆ [0-9A-F]). Require at least one A-F LETTER for
  // the hex-color rejection so digits-only tokens are kept.
  const isHexColor = (v: string) =>
    (/^[0-9A-F]{3}$/.test(v) || /^[0-9A-F]{6}$/.test(v) || /^[0-9A-F]{8}$/.test(v))
    && /[A-F]/.test(v);
  const isHtmlJunk = (v: string) =>
    /^(CELLPADDING|CELLSPACING|BGCOLOR|BORDER|ALIGN|VALIGN|WIDTH|HEIGHT|FONT|COLOR|STYLE|CLASS|UTF|HTML|BODY|TABLE|DIV|SPAN|HEADER|FOOTER|OUTLOOK|YIV|MSO|GMAIL|XMLNS|DOCTYPE)$/.test(v) ||
    /^YIV[0-9]+$/.test(v) ||
    isHexColor(v);

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
  // Common tracking number patterns — order matters here: more
  // specific patterns first so the generic numeric fallback doesn't
  // win over them.
  const patterns = [
    /\b(1Z[A-Z0-9]{16})\b/i,                    // UPS
    /\b(94[0-9]{20})\b/,                        // FedEx
    /\b(EA[0-9]{18})\b/i,                       // DHL EA-prefix
    /\b(LP[0-9]{12,14}CN)\b/i,                  // Cainiao (AliExpress, dropshippers)
    /\b([A-Z]{2}[0-9]{9}[A-Z]{2})\b/,           // 2-letter+9-digit+2-letter (USPS, Royal Mail, DHL Deutsche Post, etc.)
    /\b([A-Z][0-9]{9}[A-Z]{2})\b/i,             // Royal Mail (1-letter prefix)
    /\b([0-9]{12,22})\b/,                       // Generic numeric (DHL/Correos/etc.)
    /\b([0-9]{10})\b/,                          // DHL Express US 10-digit (last — most permissive)
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

  // SENDER WINS over tracking-number heuristics. The sender is the
  // authoritative carrier — `correosexpress.com` is unambiguously
  // Correos, no matter what the tracking-number digit pattern looks
  // like. Caught in the wild: the Correos shipment for tracking
  // 9317861133610319 was being labeled "Generic" because the
  // numeric-tracking branch fired before the sender check.
  if (lowerSender.includes('correosexpress')) return 'Correos Express';
  if (lowerSender.includes('correos'))        return 'Correos';
  if (lowerSender.includes('ctt.pt'))          return 'CTT';
  if (lowerSender.includes('dhl.'))            return 'DHL';
  if (lowerSender.includes('ups.com'))         return 'UPS';
  if (lowerSender.includes('fedex.com'))       return 'FedEx';
  if (lowerSender.includes('usps.com'))        return 'USPS';
  if (lowerSender.includes('royalmail.com'))   return 'Royal Mail';
  if (lowerSender.includes('postnl.nl') || lowerSender.includes('post.nl')) return 'PostNL';
  if (lowerSender.includes('gls-group') || lowerSender.includes('gls-pakket')) return 'GLS';
  if (lowerSender.includes('dpd.'))            return 'DPD';
  if (lowerSender.includes('colissimo'))       return 'Colissimo';
  if (lowerSender.includes('laposte.fr'))      return 'La Poste';
  if (lowerSender.includes('mondialrelay'))    return 'Mondial Relay';
  if (lowerSender.includes('inpost'))          return 'InPost';
  if (lowerSender.includes('chronopost'))      return 'Chronopost';
  if (lowerSender.includes('tnt.com'))         return 'TNT';

  if (trackingNumber) {
    if (trackingNumber.startsWith('1Z')) return 'UPS';
    if (/^94/.test(trackingNumber)) return 'FedEx';
    if (/^EA/i.test(trackingNumber)) return 'DHL';
    // ISO-3166-style country suffix is the disambiguator for the
    // [2 letters][9 digits][2 letters] format. DHL Deutsche Post
    // uses ...DE, La Poste / Colissimo use ...FR, Royal Mail
    // typically ...GB, Cainiao ...CN. Caught after DemoOutdoors's
    // DEMO-DHL-TRACK-001 got tagged Royal Mail.
    if (/^[A-Z]{2}[0-9]{9}DE$/.test(trackingNumber)) return 'DHL';
    if (/^[A-Z]{2}[0-9]{9}FR$/.test(trackingNumber)) return 'La Poste';
    if (/^[A-Z]{2}[0-9]{9}CN$/.test(trackingNumber)) return 'Cainiao';
    if (/^[A-Z]{2}[0-9]{9}[A-Z]{2}$/.test(trackingNumber)) return 'Royal Mail';
    // Cainiao "LP{12-14 digits}CN" — used by AliExpress / Shein and
    // by some EU dropshippers (Vulkit). Two-letter prefix + digits +
    // CN suffix is the unambiguous signature.
    if (/^LP[0-9]{12,14}CN$/i.test(trackingNumber)) return 'Cainiao';
    if (/^[0-9]{12,22}$/.test(trackingNumber)) return 'Generic';
    // 10-digit numeric-only is the DHL Express US format. Less
    // common globally but worth catching when the sender domain
    // didn't disambiguate (Jacques Marie Mage shipped via DHL with
    // tracking 2823872855, sender shop@jacquesmariemage.com).
    if (/^[0-9]{10}$/.test(trackingNumber)) return 'DHL';
  }

  // Body-text fallback when sender + tracking-number both miss.
  if (lowerBody.includes('correos express'))   return 'Correos Express';
  if (lowerBody.includes('correos'))            return 'Correos';
  if (lowerBody.includes('ctt'))                return 'CTT';
  if (lowerBody.includes('ups'))                return 'UPS';
  if (lowerBody.includes('fedex'))              return 'FedEx';
  if (lowerBody.includes('dhl'))                return 'DHL';
  if (lowerBody.includes('usps'))               return 'USPS';
  if (lowerBody.includes('royal mail'))         return 'Royal Mail';
  if (lowerBody.includes('postnl') || lowerBody.includes('post nl')) return 'PostNL';
  if (lowerBody.includes('gls'))                return 'GLS';
  if (lowerBody.includes('dpd'))                return 'DPD';
  if (lowerBody.includes('colissimo'))          return 'Colissimo';

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
 * merchants (Vulkit, DemoOutdoors, Matador) were storing the wrong number.
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

  // Anchored-total only — find the rightmost "Total..." label (multilingual)
  // and pick the next amount within ~120 chars after it.
  //
  // The previous "Strategy 2" fallback returned the LARGEST currency
  // amount in the body when no anchor was found. That fallback was the
  // direct cause of the Amex trip-reminder false positive ("$550 average
  // savings" was extracted as the order total). A null total is honest;
  // a wrong total is worse than no total. The LLM second-pass is good at
  // recovering totals when keyword matching fails.
  const anchorRe = /(?:grand\s+total|order\s+total|total\s+(?:price|amount|due|paid)|total\s+a\s+pagar|importe\s+total|total\s+à\s+payer|gesamtbetrag|totaalbedrag|^total\b|\btotal\b)\s*[:\s]*/gi;
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

  return { amount: null, currency: 'USD' };
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
