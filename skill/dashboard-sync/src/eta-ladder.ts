/**
 * eta-ladder.ts
 *
 * Pure 3-tier ETA resolver for the order tracker. Picks the single
 * best ETA across three sources, in strict priority order:
 *
 *   email  (carrier-email parsed at ingest)  >
 *   17track (estimated_delivery_date from polling) >
 *   heuristic (carrier-transit estimate)
 *
 * Returns { eta_at, eta_source } for the winning tier, or null when
 * no tier has a value.
 *
 * IMPORTANT — null is a no-op, never a blank. Callers merge the result
 * with `...(etaUpdate ?? {})`. A null resolution therefore writes
 * NOTHING, so it can never overwrite (blank) an already-stored ETA
 * from a higher-priority source. A non-null result only ever raises
 * the ETA to the best currently-available tier; it does not blank a
 * field. The DB-level priority guard (resolve-eta.ts /
 * resolveETAUpdate) still protects against a lower tier overwriting a
 * higher one already persisted; this ladder picks the best *incoming*
 * tier before that guard runs.
 */

export interface ETATiers {
  email: string | null;
  seventeenTrack: string | null;
  heuristic: string | null;
}

export interface ResolvedETA {
  eta_at: string;
  eta_source: 'email' | '17track' | 'heuristic';
}

export function resolveETA(tiers: ETATiers): ResolvedETA | null {
  if (tiers.email) return { eta_at: tiers.email, eta_source: 'email' };
  if (tiers.seventeenTrack) return { eta_at: tiers.seventeenTrack, eta_source: '17track' };
  if (tiers.heuristic) return { eta_at: tiers.heuristic, eta_source: 'heuristic' };
  return null;
}
