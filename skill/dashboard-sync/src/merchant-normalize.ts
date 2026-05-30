/**
 * merchant-normalize.ts
 *
 * Canonical merchant-name normalizer. Pure and side-effect-free so it can be
 * unit-tested in isolation.
 *
 * WHY THIS EXISTS:
 *   Fragmented merchant names spawn duplicate order rows. The same seller shows
 *   up as "Amazon", "Amazon.es", "Amazon.nl", "amazon.co.uk" (per-locale TLDs)
 *   or under brand-alias variants ("TAP Air Portugal" / "TAP Portugal" /
 *   "Transportes Aéreos Portugueses"). Each spelling produced a different
 *   `normalized_merchant`, so shipment-to-order matching missed and we created
 *   phantom/duplicate orders. canonicalMerchant collapses (a) country-code TLD
 *   suffixes and (b) a small curated alias table down to one stable key.
 *
 * NOTE: the combining-diacritics strip uses the EXPLICIT unicode escape
 * ̀-ͯ rather than a literal combining-mark character class — the
 * literal range has repeatedly been silently eaten by editors/tooling in this
 * repo (see R8/R10 audit history), which would break diacritic folding.
 */

const ALIASES: ReadonlyArray<[RegExp, string]> = [
  [/^tap\b|transportes a[eé]reos portugueses|^tap air|^tap portugal/i, 'tap'],
  [/^vista alegre/i, 'vista alegre'],
];

function stripDiacritics(s: string): string {
  return s.normalize('NFD').replace(/[\u0300-\u036f]/g, '');
}

export function canonicalMerchant(name: string): string {
  const base = stripDiacritics(name).toLowerCase().trim();
  for (const [re, canonical] of ALIASES) {
    if (re.test(base)) return canonical;
  }
  const tldStripped = base.replace(/\.(com|co\.uk|co|es|nl|de|fr|it|pt|eu)$/i, '');
  return tldStripped;
}
