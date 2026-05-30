/**
 * normalize-tracking.ts
 *
 * Pure tracking-number normalizer. Pulled out as a standalone, side-effect-free
 * function so it can be unit-tested in isolation and reused across the pipeline.
 *
 * WHY THIS EXISTS:
 *   1. Multi-piece freeze bug — carriers (DHL, GLS, …) regularly pack several
 *      tracking numbers into ONE string, separated by "/" or ",", e.g.
 *      "7197712620 / 001959496839433548". The old code treated that whole blob
 *      as a single tracking_number, so 17track lookups froze/failed and the UI
 *      showed one un-trackable row instead of N trackable shipments.
 *   2. Phantom-row prevention — empty/whitespace/junk inputs used to slip
 *      through and create "pending" shipment rows with no real tracking number
 *      (phantoms). Rejecting empties and length-implausible pieces here, at the
 *      source, stops those duplicate/phantom rows from ever being written.
 *
 * Splits on "/" and ",", trims each piece, drops anything implausibly
 * short/long or containing separator/whitespace residue, and dedups.
 */

const MIN_LEN = 6;
const MAX_LEN = 40;
const BAD_CHARS = /[\s,/\\]/;

function isValidPiece(p: string): boolean {
  return p.length >= MIN_LEN && p.length <= MAX_LEN && !BAD_CHARS.test(p);
}

export function normalizeTrackingNumbers(raw: string | null | undefined): string[] {
  if (!raw) return [];
  const pieces = raw.split(/[/,]/).map(s => s.trim()).filter(s => s.length > 0);
  const valid = pieces.filter(isValidPiece);
  return [...new Set(valid)];
}
