/**
 * physical-vs-digital.ts
 *
 * Apple-bug fix (2026-04-27): the orders pipeline was classifying
 * digital purchases (App Store, iCloud, in-app subscriptions) as
 * physical-goods orders even though the email contained no shipping
 * address and explicitly mentioned "available in your library" /
 * "your download is ready" phrases.
 *
 * This module runs in handlePurchaseConfirmation AFTER tier1/LLM have
 * said "yes, this is a purchase." It decides whether the purchase is
 * physical (default — preserves existing behavior) or digital. Digital
 * purchases write with status='digital', skip shipment creation, and
 * are hidden from the default Today/Orders queries (visible in Past
 * Orders sheet).
 *
 * Decision rule (tunable; lives as a constant for easy adjustment):
 *
 *   digital  if  digital_phrases_found.length >= 1
 *           AND  shipping_address_in_body == false
 *           AND  tangible_keywords.length == 0
 *   physical otherwise (default — preserves existing behavior)
 *
 * Conservative: requires unambiguous digital signals AND absence of
 * tangible signals to flip from default. False-positive cost (missing
 * an Apple iPhone shipment) is much higher than false-negative cost
 * (a digital purchase shows up with "tracking pending" forever, which
 * the user can swipe-correct).
 */

export type PhysicalDigitalDecision = 'physical' | 'digital';

export interface PhysicalDigitalSignals {
  shipping_address_in_body: boolean;
  digital_phrases_found: string[];
  tangible_keywords: string[];
}

export interface PhysicalDigitalResult {
  decision: PhysicalDigitalDecision;
  signals: PhysicalDigitalSignals;
}

// ─── Whitelisted digital phrases ─────────────────────────────────────
// Curated to match high-precision phrases (avoid bare "download" which
// also appears in "download our app" footers on physical-goods emails).
const DIGITAL_PHRASES: ReadonlyArray<string> = [
  'your download',
  'available in your library',
  'redeem your code',
  'your subscription is active',
  'access your purchase',
  'license key',
  'activation key',
  'download link',
  'has been added to your account',
  'your icloud',
  'your apple id',
  // Multilingual variants — PT/ES/DE locales the user actually receives
  'sua compra digital',
  'compra digital',
  'su compra digital',
  'tu compra digital',
  'descarga disponible',
  'téléchargement disponible',
  'votre abonnement',
  'ihr abonnement',
];

// ─── Shipping-address regex ──────────────────────────────────────────
// Looks for unambiguous postal-address signals: explicit "Ship to:" /
// "Delivery address:" labels, OR a postal-code shape near a country/
// region marker. Conservative — false-negative on weird formats is OK
// (defaults to physical, which is the existing behavior).
const SHIPPING_ADDRESS_PATTERNS: ReadonlyArray<RegExp> = [
  /\b(ship|delivery|shipping)\s*(to|address)\s*[:.]?/i,
  /\b(enviar|entrega|envío|envio)\s*(a|para|à)\s*[:.]?/i,    // PT/ES
  /\bversand\s*an\b/i,                                         // DE
  /\bexpédier?\s*à\b/i,                                        // FR
  // US zip: 5-digit code at end of an address-shaped line
  /\b\d{5}(?:-\d{4})?\s*\n/,
  // EU postal codes near country marker (loose — reject trivial number-then-text)
  /\b\d{4,5}\s+[A-ZÁÉÍÓÚÄÖÜß][a-záéíóúñäöüß]+(?:\s+[A-ZÁÉÍÓÚÄÖÜß][a-záéíóúñäöüß]+)?\s*[\n,]/,
];

// ─── Tangible-goods keywords (reuse pipeline vocabulary) ─────────────
// These are the same keywords tier1 already matches. We re-check them
// here because the decision is local to this module — we don't want
// to thread Tier1 internals through the call site.
const TANGIBLE_KEYWORDS: ReadonlyArray<string> = [
  'shipped', 'shipping', 'tracking', 'tracking number', 'package',
  'delivery', 'delivered', 'courier', 'parcel', 'will arrive',
  'enviado', 'envío', 'envio', 'rastreo',                  // ES/PT
  'expédié', 'colis', 'livraison',                         // FR
  'versand', 'sendung', 'paket', 'lieferung',              // DE
];

/**
 * Decide whether a confirmed purchase is physical or digital.
 *
 * @param subject — email subject (used for keyword scan)
 * @param body    — email body, plain text. HTML should be stripped before this call.
 */
export function detectPhysicalVsDigital(
  subject: string,
  body: string,
): PhysicalDigitalResult {
  const text = `${subject}\n${body}`;
  const lower = text.toLowerCase();

  const digital_phrases_found: string[] = [];
  for (const phrase of DIGITAL_PHRASES) {
    if (lower.includes(phrase)) digital_phrases_found.push(phrase);
  }

  const tangible_keywords: string[] = [];
  for (const kw of TANGIBLE_KEYWORDS) {
    // Word-boundary match so "shipped" doesn't fire on "Shipping Tax: $0".
    const re = new RegExp(`\\b${kw.replace(/[-/\\^$*+?.()|[\]{}]/g, '\\$&')}\\b`, 'i');
    if (re.test(text)) tangible_keywords.push(kw);
  }

  const shipping_address_in_body = SHIPPING_ADDRESS_PATTERNS.some(p => p.test(text));

  const decision: PhysicalDigitalDecision =
    digital_phrases_found.length >= 1
      && !shipping_address_in_body
      && tangible_keywords.length === 0
        ? 'digital'
        : 'physical';

  return {
    decision,
    signals: {
      shipping_address_in_body,
      digital_phrases_found,
      tangible_keywords,
    },
  };
}

// ─── Hard-category sender excludes (classification cascade) ──────────
// Some senders can NEVER ship a tangible package no matter what their
// email body says — airlines, restaurants, domain registrars,
// brokerages, SaaS subscriptions, rideshare. The classification
// cascade consults this list AFTER the carrier short-circuit and the
// learned merchant_rules lookup but BEFORE the LLM, so these never burn
// an LLM call and never surface in the package tracker.
//
// Each entry maps a domain-matching regex → a coarse category label
// (returned for telemetry / the cascade `reason`). Anchored with
// `(^|\.)…$` so a subdomain (mail.flytap.com) still matches while a
// look-alike (notflytap.com) does not.
const HARD_CATEGORY_DOMAINS: ReadonlyArray<[RegExp, string]> = [
  [/(^|\.)(flytap|ryanair|lufthansa|united|aa|delta|iberia)\.com$/i, 'airline'],
  [/(^|\.)(noma\.dk|opentable\.com|thefork\.com|resy\.com)$/i, 'restaurant'],
  [/(^|\.)(godaddy|namecheap|cloudflare|gandi)\.com$/i, 'domains'],
  [/(^|\.)(schwab|fidelity|vanguard|revolut|wise|amex|americanexpress)\.com$/i, 'financial'],
  [/(^|\.)(cleancloud|notion|figma|slack|zoom|spotify|netflix)\.com$/i, 'service'],
  [/(^|\.)(uber|lyft)\.com$/i, 'rideshare'],
];

/**
 * Return a coarse category label when the sender domain belongs to a
 * business that never ships a physical package (airline, restaurant,
 * domains, financial, service, rideshare). Returns null for everything
 * else — including real physical merchants — so the caller falls
 * through to the LLM stage of the cascade.
 */
export function hardCategoryExclude(senderEmail: string | null | undefined): string | null {
  if (!senderEmail) return null;
  const at = senderEmail.lastIndexOf('@');
  if (at < 0) return null;
  const domain = senderEmail.slice(at + 1).toLowerCase().trim();
  for (const [re, cat] of HARD_CATEGORY_DOMAINS) {
    if (re.test(domain)) return cat;
  }
  return null;
}
