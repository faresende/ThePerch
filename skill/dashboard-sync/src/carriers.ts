/**
 * carriers.ts
 *
 * Carrier-sender detection for the classification cascade's first
 * short-circuit. When an inbound commerce email comes straight from a
 * known parcel carrier (DHL, UPS, CTT, …) the message is, by
 * definition, about a tangible package in transit — so the cascade can
 * classify it 'physical' with high confidence WITHOUT reaching the
 * learned merchant_rules lookup, hard-category excludes, or the LLM.
 *
 * Pure module: no Supabase / network imports, so its tests stay
 * deterministic.
 */

// Curated set of carrier mail domains the user actually receives parcel
// notifications from (EU + PT/ES-heavy, plus the global big four).
const CARRIER_DOMAINS: ReadonlyArray<string> = [
  'dhl.com', 'dhl.de', 'dpdhl.com', 'ups.com', 'fedex.com', 'usps.com',
  'ctt.pt', 'gls-group.com', 'gls-group.eu', 'dpd.com', 'tnt.com', 'aramex.com',
  'royalmail.com', 'correos.es', 'seur.com', 'mrw.es',
];

/**
 * Return true when the sender's email domain belongs to a known parcel
 * carrier (exact match OR a subdomain such as `mail.dhl.com`).
 *
 * Null/blank/malformed senders return false — the caller falls through
 * to the rest of the cascade.
 */
export function isCarrierSender(senderEmail: string | null | undefined): boolean {
  if (!senderEmail) return false;
  const at = senderEmail.lastIndexOf('@');
  if (at < 0) return false;
  const domain = senderEmail.slice(at + 1).toLowerCase().trim();
  return CARRIER_DOMAINS.some(d => domain === d || domain.endsWith(`.${d}`));
}
