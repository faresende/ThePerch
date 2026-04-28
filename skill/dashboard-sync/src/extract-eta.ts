/**
 * extract-eta.ts
 *
 * Pulls estimated-delivery-date candidates from carrier shipping
 * email subject + body. Mirrors the shape of tracking-candidates.ts:
 * enumerates candidates with source + rank, picks the winner via
 * `pickETA`, returns ALL candidates so parse_trace can record what
 * was passed over.
 *
 * Phase 1 ETA. See docs/superpowers/specs/2026-04-27-orders-eta-design.md.
 *
 * Pattern coverage (matches existing scanner locales):
 *   EN: "Expected delivery: Tuesday, May 1"
 *       "Estimated delivery: May 1, 2026"
 *       "Arrives by May 1" / "Will arrive on May 1"
 *       "Delivery date: 2026-05-01"
 *   PT: "estimada entrega" / "data de entrega"
 *   ES: "entrega prevista" / "fecha de entrega"
 *   DE: "lieferung am" / "voraussichtliches lieferdatum"
 *   FR: "livraison prévue" / "date de livraison"
 *   NL: "verwachte levering" / "leverdatum"
 *
 * Sanity rejects: candidates parsing to a date >180 days in the
 * future or already in the past relative to the email date are
 * dropped. These are usually order numbers / postal codes / prices
 * misread as dates.
 */

export type ETACandidateSource =
  | 'body_regex_near_keyword'      // matched within KEYWORD_PROXIMITY chars of an ETA keyword
  | 'body_regex_isolated';         // bare date, no surrounding context

export interface ETACandidate {
  date: Date;                      // parsed UTC date (start-of-day)
  source: ETACandidateSource;
  rank: number;                    // 60 / 40 (mirrors tracking ranks)
  matchedText: string;             // raw substring captured
  bodyOffset: number;              // tie-break: earlier in body wins
}

const RANK: Record<ETACandidateSource, number> = {
  body_regex_near_keyword: 60,
  body_regex_isolated:     40,
};

// ─── Multilingual ETA keywords ───────────────────────────────────────
// When a candidate date appears within KEYWORD_PROXIMITY chars BEFORE
// or AFTER one of these phrases, it ranks `body_regex_near_keyword`
// (60). Otherwise it ranks `body_regex_isolated` (40).
const ETA_KEYWORDS: ReadonlyArray<string> = [
  'expected delivery',
  'estimated delivery',
  'estimated arrival',
  'delivery date',
  'arrives by',
  'arrives on',
  'will arrive',
  'arrival date',
  'delivery on',
  'estimada entrega',          // PT
  'previsão de entrega',
  'data de entrega',
  'entrega prevista',           // ES
  'fecha de entrega',
  'fecha estimada',
  'lieferung am',               // DE
  'lieferdatum',
  'voraussichtlich',
  'livraison prévue',           // FR
  'date de livraison',
  'arrivée prévue',
  'verwachte levering',         // NL
  'leverdatum',
  'verwachte bezorging',
];

const KEYWORD_PROXIMITY = 50;     // chars

// ─── Multilingual month names ────────────────────────────────────────
// Maps 1-3 character month prefixes (lowercased) → 1-12. Covers
// EN/PT/ES/DE/FR/NL. Extra-long names hit on prefix; "septembre"
// matches via "sep".
const MONTH_PREFIX: Record<string, number> = {
  // EN
  jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6,
  jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12,
  // PT
  fev: 2, abr: 4, mai: 5, ago: 8, set: 9, out: 10, dez: 12,
  // ES
  ene: 1, ago_es: 8,                     // most overlap with EN/PT
  // DE — month names are mostly EN-similar except some
  mär: 3, mai_de: 5, okt: 10, dez_de: 12,
  // FR
  jan_fr: 1, fév: 2, avr: 4, mai_fr: 5, jui: 6, juil: 7,
  aoû: 8, sep_fr: 9, oct_fr: 10, déc: 12,
  // NL
  mrt: 3, mei: 5, okt_nl: 10,
};

// Strip trailing locale-disambiguation suffixes when looking up.
function lookupMonth(token: string): number | null {
  const t = token.toLowerCase().slice(0, 3);
  if (t in MONTH_PREFIX) return MONTH_PREFIX[t];
  // Try special-cased entries (e.g. "mai" appears in PT/DE/FR).
  // The bare "mai" → 5 already covered by PT.
  // For accented variants, normalize.
  const norm = token.toLowerCase()
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .slice(0, 3);
  if (norm in MONTH_PREFIX) return MONTH_PREFIX[norm];
  return null;
}

// ─── Date-shape regexes ──────────────────────────────────────────────
// Each pattern captures a date. We try them all and collect every
// successful match. Date parsing is done in `parseDateMatch` —
// returning null if the captured groups don't form a valid date.

interface DatePattern {
  re: RegExp;
  parse: (match: RegExpExecArray, refYear: number) => Date | null;
}

const DATE_PATTERNS: ReadonlyArray<DatePattern> = [
  // ISO 8601: 2026-05-01 or 2026/05/01
  {
    re: /\b(20\d{2})[-/](\d{1,2})[-/](\d{1,2})\b/g,
    parse: (m) => safeDate(parseInt(m[1]), parseInt(m[2]), parseInt(m[3])),
  },
  // "May 1, 2026" / "May 1 2026" — month name + day [+ year]
  {
    re: /\b([A-Za-zÀ-ÿ]{3,12})\s+(\d{1,2})(?:,?\s+(20\d{2}))?\b/g,
    parse: (m, refYear) => {
      const month = lookupMonth(m[1]);
      if (!month) return null;
      const day = parseInt(m[2]);
      const year = m[3] ? parseInt(m[3]) : refYear;
      return safeDate(year, month, day);
    },
  },
  // "1 May 2026" / "1 May" / "1 de mayo de 2026" — day + month name
  {
    re: /\b(\d{1,2})(?:\s+de)?\s+([A-Za-zÀ-ÿ]{3,12})(?:\s+(?:de\s+)?(20\d{2}))?\b/g,
    parse: (m, refYear) => {
      const day = parseInt(m[1]);
      const month = lookupMonth(m[2]);
      if (!month) return null;
      const year = m[3] ? parseInt(m[3]) : refYear;
      return safeDate(year, month, day);
    },
  },
  // Note: numeric DD/MM/YYYY or MM/DD/YYYY pattern is intentionally
  // omitted. "04/10/2026" is irretrievably ambiguous — could be Apr
  // 10 (US convention) or Oct 4 (EU convention). Caught in the wild
  // when the EU-default branch read a NOMOS FedEx (US merchant)
  // email's "04/10/2026" as Oct 4 instead of Apr 10. Better to skip
  // the candidate entirely than to bake in a guess that's wrong half
  // the time. ISO dates (2026-04-10) and month-name forms ("Apr 10")
  // are unambiguous and stay covered above. If a carrier emits only
  // numeric dates, no ETA chip — falls back to "Updated <date>".
];

// ─── Validation ──────────────────────────────────────────────────────

function safeDate(year: number, month: number, day: number): Date | null {
  if (year < 2000 || year > 2100) return null;
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > 31) return null;
  // Construct UTC date at start-of-day so timezone shifts don't move
  // the date by ±1 day for late-night users.
  const d = new Date(Date.UTC(year, month - 1, day, 0, 0, 0, 0));
  // Date constructor accepts overflow values (e.g. month=13 → Jan next
  // year). Guard against this by checking the round-trip.
  if (
    d.getUTCFullYear() !== year ||
    d.getUTCMonth() !== month - 1 ||
    d.getUTCDate() !== day
  ) {
    return null;
  }
  return d;
}

const MAX_FUTURE_DAYS = 180;
const MAX_PAST_DAYS = 1;     // emails about future delivery; same-day OK, prior-day mostly garbage

function isReasonableETA(date: Date, refDate: Date): boolean {
  const diffMs = date.getTime() - refDate.getTime();
  const diffDays = diffMs / (1000 * 60 * 60 * 24);
  return diffDays >= -MAX_PAST_DAYS && diffDays <= MAX_FUTURE_DAYS;
}

// ─── Main API ────────────────────────────────────────────────────────

/**
 * Extract every plausible ETA candidate from subject + body. Each
 * candidate carries source + rank + the raw matched text so the
 * parse-trace can show what was selected and what was discarded.
 *
 * @param subject — email subject
 * @param body    — email body, plain text recommended
 * @param now     — reference date for "is this in a reasonable
 *                  delivery window?" sanity check. Defaults to
 *                  `new Date()`.
 */
export function extractETACandidates(
  subject: string,
  body: string,
  now: Date = new Date(),
): ETACandidate[] {
  const candidates: ETACandidate[] = [];
  const text = `${subject}\n${body}`;
  const lower = text.toLowerCase();
  const refYear = now.getUTCFullYear();

  // Pre-compute keyword positions for fast proximity check.
  const keywordPositions: number[] = [];
  for (const kw of ETA_KEYWORDS) {
    let idx = lower.indexOf(kw);
    while (idx !== -1) {
      keywordPositions.push(idx);
      idx = lower.indexOf(kw, idx + 1);
    }
  }

  const seenOffsets = new Set<number>();

  for (const { re, parse } of DATE_PATTERNS) {
    re.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(text)) !== null) {
      // De-dup overlapping matches (multiple patterns can fire on
      // the same substring — keep the first hit by offset).
      if (seenOffsets.has(m.index)) continue;
      seenOffsets.add(m.index);

      const date = parse(m, refYear);
      if (!date) continue;
      if (!isReasonableETA(date, now)) continue;

      const offset = m.index;
      const nearKeyword = keywordPositions.some(
        kp => Math.abs(kp - offset) <= KEYWORD_PROXIMITY
      );

      candidates.push({
        date,
        source: nearKeyword ? 'body_regex_near_keyword' : 'body_regex_isolated',
        rank: nearKeyword ? RANK.body_regex_near_keyword : RANK.body_regex_isolated,
        matchedText: m[0],
        bodyOffset: offset,
      });
    }
  }

  return candidates;
}

/**
 * Pick the winning ETA candidate by rank, then by tie-breaks
 * (earlier in body, then earliest date).
 *
 * Returns null when there are no candidates.
 */
export function pickETA(
  candidates: ETACandidate[],
  _now: Date = new Date(),
): ETACandidate | null {
  if (candidates.length === 0) return null;
  const sorted = [...candidates].sort((a, b) => {
    if (b.rank !== a.rank) return b.rank - a.rank;
    if (a.bodyOffset !== b.bodyOffset) return a.bodyOffset - b.bodyOffset;
    return a.date.getTime() - b.date.getTime();
  });
  return sorted[0];
}
