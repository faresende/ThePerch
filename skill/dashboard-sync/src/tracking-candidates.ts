/**
 * tracking-candidates.ts
 *
 * Phase 1.5 — Body & Fit fix: replace first-match-wins tracking-number
 * extraction with priority-rank-wins. The old `extractTrackingNumber()`
 * returned whatever pattern matched first in the body; for emails that
 * contain BOTH a carrier-authoritative URL (e.g. dhl.com/track/...) AND
 * a less-authoritative number elsewhere (a returns-portal redirect,
 * an unrelated UPS reference, etc.), it would silently pick wrong.
 *
 * This module:
 *   - Enumerates ALL plausible tracking candidates from subject/body
 *     with their source label and rank.
 *   - Picks the highest-ranked candidate as the winner.
 *   - Returns ALL candidates so the parse-trace can record what was
 *     discarded and why — feeding the rule-distillation pipeline
 *     (Phase 2) with cases where the picker chose differently than
 *     the user expected.
 *
 * Rank table (lower number = lower priority; ties broken below):
 *   100  carrier_specific_header        e.g. X-DHL-Tracking-Number header
 *                                       (NOT plumbed yet — slot reserved)
 *    80  url_in_carrier_owned_link      URL on dhl.com, ups.com, etc.
 *    60  body_regex_near_tracking_kw    "Tracking number: XYZ" — kw within 40 chars
 *    40  body_regex_isolated            matches carrier format, no surrounding context
 *    20  url_in_third_party_redirect    parcel-tracker.com, packagetrackr.com
 *
 * Tie-breaks (in order):
 *   1. Appears earlier in the body
 *   2. Longest match (longer numbers are usually carrier-issued)
 */

export const TRACKING_CANDIDATE_SOURCES = [
  'carrier_specific_header',
  'url_in_carrier_owned_link',
  'body_regex_near_tracking_kw',
  'body_regex_isolated',
  'url_in_third_party_redirect',
] as const;

export type TrackingCandidateSource = typeof TRACKING_CANDIDATE_SOURCES[number];

export interface TrackingCandidate {
  number: string;
  carrier: string | null;
  source: TrackingCandidateSource;
  rank: number;
  /** Byte offset in body where the candidate appears — used as tie-break. */
  bodyOffset: number;
}

const RANK: Record<TrackingCandidateSource, number> = {
  carrier_specific_header:    100,
  url_in_carrier_owned_link:   80,
  body_regex_near_tracking_kw: 60,
  body_regex_isolated:         40,
  url_in_third_party_redirect: 20,
};

// ─── Carrier-owned domains and their canonical labels ────────────────
// When a tracking URL is on one of these domains, the candidate is
// considered authoritative (rank 80). The carrier label is also
// inferred from the host name in this same pass.
const CARRIER_DOMAINS: Array<{ host: RegExp; carrier: string }> = [
  { host: /\bdhl\.com\b|\bdhl\.de\b|\bdhl\.[a-z]{2,3}\b/i,                  carrier: 'DHL' },
  { host: /\bups\.com\b/i,                                                    carrier: 'UPS' },
  { host: /\bfedex\.com\b/i,                                                  carrier: 'FedEx' },
  { host: /\busps\.com\b/i,                                                   carrier: 'USPS' },
  { host: /\broyalmail\.com\b/i,                                              carrier: 'Royal Mail' },
  { host: /\bctt\.pt\b/i,                                                     carrier: 'CTT' },
  { host: /\bcorreosexpress\.com\b/i,                                         carrier: 'Correos Express' },
  { host: /\bcorreos\.es\b|\bcorreos\.com\b/i,                                carrier: 'Correos' },
  { host: /\bpostnl\.[a-z]{2,3}\b|\bpost\.nl\b/i,                             carrier: 'PostNL' },
  { host: /\bgls-group\.eu\b|\bgls-pakket\.[a-z]{2,3}\b/i,                    carrier: 'GLS' },
  { host: /\bdpd\.[a-z]{2,3}\b/i,                                             carrier: 'DPD' },
  { host: /\bcolissimo\.fr\b|\blaposte\.fr\b/i,                               carrier: 'Colissimo' },
];

const THIRD_PARTY_TRACKER_DOMAINS = [
  /\bparcel(?:tracker)?\.com\b/i,
  /\bpackagetrackr\.com\b/i,
  /\b17track\.net\b/i,
  /\baftership\.com\b/i,
  /\btrackingmore\.com\b/i,
];

// Tracking-number patterns reused from email-classifier's
// extractTrackingNumber. Kept locally so this module is self-contained.
// Order matters: more specific patterns first. The generic numeric
// fallback at the bottom would otherwise eat tracking numbers that
// have a meaningful country/carrier suffix.
const TRACKING_NUMBER_PATTERNS: ReadonlyArray<{ re: RegExp; carrier: string | null }> = [
  { re: /\b(1Z[A-Z0-9]{16})\b/i,             carrier: 'UPS' },
  { re: /\b(EA[0-9]{18})\b/i,                carrier: 'DHL' },
  { re: /\b(94[0-9]{20})\b/,                 carrier: 'FedEx' },
  // Cainiao "LP{12-14 digits}CN" — AliExpress / Shein / EU dropshippers.
  { re: /\b(LP[0-9]{12,14}CN)\b/i,           carrier: 'Cainiao' },
  // 2-letter prefix + 9 digits + 2-letter country suffix. The country
  // suffix gets fingerprinted in inferCarrier (DE→DHL, FR→La Poste,
  // CN→Cainiao, GB/etc→Royal Mail).
  { re: /\b([A-Z]{2}[0-9]{9}[A-Z]{2})\b/,    carrier: null },
  // Generic numeric tracking (12-22 digits) — DHL Deutsche Post,
  // Correos Express, DPD-without-prefix, and many other postal carriers.
  { re: /\b([0-9]{12,22})\b/,                carrier: null },
  // DHL Express US 10-digit numeric. Most permissive — must be last
  // to avoid matching the leading 10 digits of longer numbers.
  { re: /\b([0-9]{10})\b/,                   carrier: 'DHL' },
];

const TRACKING_KEYWORDS = [
  'tracking number',
  'tracking #',
  'track your package',
  'track your order',
  'track your shipment',
  'tracking code',
  'consignment number',
  'sendungsnummer',                  // DE
  'número de seguimiento',           // ES
  'numero de seguimiento',
  'número de rastreio',              // PT
  'numero di tracciamento',          // IT
  'numéro de suivi',                 // FR
];

const KEYWORD_PROXIMITY = 40;  // chars

/**
 * Extract all tracking-number candidates from an email's text content,
 * each tagged with source + rank. The caller picks the winner via
 * `pickWinner()` and feeds the full list into the parse-trace.
 *
 * @param subject — email subject
 * @param body    — email body (plain text recommended; HTML is handled
 *                  but URL extraction is more reliable on plain text)
 * @param sender  — sender email; used as a hint for carrier inference
 *                  on numeric candidates
 */
export function extractTrackingCandidates(
  subject: string,
  body: string,
  sender: string,
): TrackingCandidate[] {
  const candidates: TrackingCandidate[] = [];
  const text = `${subject}\n${body}`;

  // ─── Pass 1: URLs ──────────────────────────────────────────────────
  // Find every URL in the text, classify by host, extract any
  // tracking-number-shaped tail in the URL.
  const URL_RE = /\bhttps?:\/\/[^\s<>"')]+/gi;
  let urlMatch: RegExpExecArray | null;
  while ((urlMatch = URL_RE.exec(text)) !== null) {
    const url = urlMatch[0];
    const offset = urlMatch.index;

    // Try each carrier domain. First hit wins for THIS url.
    let carrier: string | null = null;
    let isCarrierOwned = false;
    for (const cd of CARRIER_DOMAINS) {
      if (cd.host.test(url)) {
        carrier = cd.carrier;
        isCarrierOwned = true;
        break;
      }
    }

    if (!isCarrierOwned) {
      // Third-party redirect tracker?
      const isThirdParty = THIRD_PARTY_TRACKER_DOMAINS.some(re => re.test(url));
      if (!isThirdParty) continue;
    }

    // Extract a tracking-number-shaped substring from the URL. We try
    // each pattern; the first match wins for this URL (URLs only carry
    // one tracking number in practice).
    for (const { re, carrier: patternCarrier } of TRACKING_NUMBER_PATTERNS) {
      const m = url.match(re);
      if (m) {
        candidates.push({
          number: m[1].toUpperCase(),
          carrier: carrier ?? patternCarrier,
          source: isCarrierOwned ? 'url_in_carrier_owned_link' : 'url_in_third_party_redirect',
          rank: isCarrierOwned ? RANK.url_in_carrier_owned_link : RANK.url_in_third_party_redirect,
          bodyOffset: offset,
        });
        break;  // one number per URL
      }
    }
  }

  // ─── Pass 2: Body-text patterns ─────────────────────────────────────
  // Find all tracking-number-shaped strings in the text. For each,
  // check whether a tracking-related keyword appears within
  // KEYWORD_PROXIMITY chars before it (rank 60) — otherwise it's an
  // isolated match (rank 40).
  const lowerText = text.toLowerCase();
  for (const { re, carrier: patternCarrier } of TRACKING_NUMBER_PATTERNS) {
    const globalRe = new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g');
    let m: RegExpExecArray | null;
    while ((m = globalRe.exec(text)) !== null) {
      const number = m[1].toUpperCase();
      const offset = m.index;

      // Skip if we already have THIS number from a URL pass — URL
      // candidates outrank body candidates and we don't want
      // duplicates double-counting.
      const dup = candidates.find(c => c.number === number);
      if (dup) continue;

      // Look behind for a tracking keyword within KEYWORD_PROXIMITY chars.
      const lookbehindStart = Math.max(0, offset - KEYWORD_PROXIMITY);
      const window = lowerText.slice(lookbehindStart, offset);
      const nearKw = TRACKING_KEYWORDS.some(kw => window.includes(kw));

      candidates.push({
        number,
        carrier: patternCarrier,
        source: nearKw ? 'body_regex_near_tracking_kw' : 'body_regex_isolated',
        rank: nearKw ? RANK.body_regex_near_tracking_kw : RANK.body_regex_isolated,
        bodyOffset: offset,
      });
    }
  }

  return candidates;
}

/**
 * Pick the winning tracking candidate by rank, then by tie-breaks
 * (earlier in body, then longest match).
 *
 * Mutates the input array: marks the winner with a sentinel that the
 * caller can then map to the trace's `selected` flag. Returns the
 * winner (or null when there are no candidates).
 */
export function pickWinner(candidates: TrackingCandidate[]): TrackingCandidate | null {
  if (candidates.length === 0) return null;
  // Sort: higher rank first; then earlier offset; then longer number.
  const sorted = [...candidates].sort((a, b) => {
    if (b.rank !== a.rank) return b.rank - a.rank;
    if (a.bodyOffset !== b.bodyOffset) return a.bodyOffset - b.bodyOffset;
    return b.number.length - a.number.length;
  });
  return sorted[0];
}

/**
 * Helper: build the parse-trace's `tracking_candidates` array from a
 * candidate list + the winner. Each non-winner gets a discarded_reason.
 */
export function candidatesForTrace(
  candidates: TrackingCandidate[],
  winner: TrackingCandidate | null,
): Array<{
  number: string;
  carrier: string | null;
  source: string;
  selected: boolean;
  discarded_reason: string | null;
}> {
  return candidates.map(c => ({
    number: c.number,
    carrier: c.carrier,
    source: c.source,
    selected: !!(winner && c.number === winner.number && c.bodyOffset === winner.bodyOffset),
    discarded_reason:
      winner && c.number === winner.number && c.bodyOffset === winner.bodyOffset
        ? null
        : 'lower_rank_than_selected',
  }));
}
