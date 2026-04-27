/**
 * resolve-eta.ts
 *
 * Shared ETA-write resolver. Both write paths (carrier-email
 * extraction in handleShippingNotification, 17track polling in
 * pollAndUpdateShipment) call this before upserting. Returns
 * the new triplet to write OR null when no update should happen.
 *
 * Rules (per design spec 2026-04-27-orders-eta-design.md):
 *   1. Never overwrite non-null with null (handles 17track silence).
 *   2. First-time write (current.eta_source is null) — accept incoming.
 *   3. Higher priority always wins, regardless of recorded_at.
 *      Priority: 17track (100) > carrier_email (50).
 *   4. Same priority — newer eta_recorded_at wins.
 */

const PRIORITY: Record<string, number> = {
  '17track': 100,
  'carrier_email': 50,
};

export interface ETATriplet {
  eta_at: Date | null;
  eta_source: string | null;
  eta_recorded_at: Date | null;
}

export interface ETAUpdate {
  eta_at: Date;            // never null in an incoming update
  eta_source: '17track' | 'carrier_email';
  eta_recorded_at: Date;
}

/**
 * Decide whether `next` should overwrite `current`. Returns the
 * value to write (== next on success), or null when no update.
 *
 * Caller convention: only call this when next.eta_at is non-null.
 * Null overwrites are filtered upstream so the resolver doesn't
 * have to special-case it (one less branch).
 */
export function resolveETAUpdate(
  current: ETATriplet,
  next: ETAUpdate,
): ETAUpdate | null {
  // First-time write — no current ETA exists.
  if (current.eta_source === null) return next;

  const newPri = PRIORITY[next.eta_source] ?? 0;
  const curPri = PRIORITY[current.eta_source] ?? 0;

  if (newPri > curPri) return next;
  if (newPri < curPri) return null;

  // Same priority — newer recorded_at wins. When the resolver is
  // called repeatedly with the same source returning the same date
  // (e.g. 17track polls every hour returning unchanged ETA), this
  // refreshes eta_recorded_at on each call. That's a feature: it
  // keeps the freshness signal accurate. Cheap; one row update.
  const curTime = current.eta_recorded_at?.getTime() ?? 0;
  return next.eta_recorded_at.getTime() > curTime ? next : null;
}
