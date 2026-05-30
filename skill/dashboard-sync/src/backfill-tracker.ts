/**
 * backfill-tracker.ts
 *
 * Phase 5 of the order-tracker rework. Pure planners that decide what the
 * one-time backfill should do to the user's existing orders and shipments.
 *
 * IMPORTANT: these functions are side-effect-free. They take rows in and
 * return a *plan* describing what a caller WOULD do. No DB access here. The
 * CLI subcommand (`backfill-tracker`) is what fetches data, runs these
 * planners, and — only under an explicit `--apply` — performs the writes.
 *
 * Order backfill (reversible — hide-not-delete):
 *   - hide    : sender domain is a hard-category exclude (airline, restaurant,
 *               domains, financial, SaaS, rideshare) → can never ship a package.
 *   - keep    : merchant is a known physical merchant → leave visible.
 *   - archive : everything else ("unsure history") → archived rather than
 *               re-queued for review, so the backfill doesn't flood the review
 *               queue with months of old, low-signal orders. Still reversible.
 *
 * Shipment repair (de-dupe + split + drop phantoms) — precondition for the
 * deferred partial-unique index on (user_id, tracking_number):
 *   - deleteEmpty  : tracking_number normalizes to nothing (phantom row).
 *   - split        : one row carries multiple tracking numbers (multi-piece).
 *   - collapseDupes: several rows share the same normalized tracking number.
 */

import { hardCategoryExclude } from './physical-vs-digital';
import { normalizeTrackingNumbers } from './normalize-tracking';

// ─── Order backfill (Task 5.1) ───────────────────────────────────────────────

export interface BackfillOrder {
  id: string;
  merchant_name: string;
  normalized_merchant: string;
  sender: string | null;
}

export interface BackfillAction {
  id: string;
  action: 'keep' | 'hide' | 'archive';
  reason: string;
}

const KNOWN_PHYSICAL: ReadonlySet<string> = new Set([
  'peak design', 'notino', 'dak coffee roasters', 'lofree', 'mukama', 'amazon', 'vista alegre', 'oura',
]);

export function planOrderBackfill(orders: BackfillOrder[]): BackfillAction[] {
  return orders.map(o => {
    const cat = hardCategoryExclude(o.sender);
    if (cat) return { id: o.id, action: 'hide', reason: `hard-category:${cat}` };
    if (KNOWN_PHYSICAL.has(o.normalized_merchant)) return { id: o.id, action: 'keep', reason: 'known-physical' };
    return { id: o.id, action: 'archive', reason: 'unsure-history' };
  });
}

// ─── Shipment repair (Task 5.2) ──────────────────────────────────────────────

export interface RepairShipment {
  id: string;
  tracking_number: string;
}

export interface RepairPlan {
  deleteEmpty: { id: string }[];
  split: { id: string; into: string[] }[];
  collapseDupes: { keep: string; drop: string[] }[];
}

export function planShipmentRepair(ships: RepairShipment[]): RepairPlan {
  const deleteEmpty: { id: string }[] = [];
  const split: { id: string; into: string[] }[] = [];
  const byNumber = new Map<string, string[]>();
  for (const s of ships) {
    const norm = normalizeTrackingNumbers(s.tracking_number);
    if (norm.length === 0) { deleteEmpty.push({ id: s.id }); continue; }
    if (norm.length > 1) { split.push({ id: s.id, into: norm }); continue; }
    const arr = byNumber.get(norm[0]) ?? []; arr.push(s.id); byNumber.set(norm[0], arr);
  }
  const collapseDupes: { keep: string; drop: string[] }[] = [];
  for (const ids of byNumber.values()) { if (ids.length > 1) collapseDupes.push({ keep: ids[0], drop: ids.slice(1) }); }
  return { deleteEmpty, split, collapseDupes };
}
