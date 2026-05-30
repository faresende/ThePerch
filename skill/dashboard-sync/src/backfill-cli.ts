/**
 * backfill-cli.ts
 *
 * DB orchestration for the `backfill-tracker` CLI subcommand. Keeps all
 * side effects (fetch / write) out of the pure planners in
 * backfill-tracker.ts.
 *
 * Two modes:
 *   - dry-run (default): fetch everything, run the planners, return the plan
 *     + counts + samples. Writes NOTHING. Read-only.
 *   - apply: actually perform the plan — set hidden/hidden_reason on orders
 *     (hide + archive; NEVER hard-delete an order), and repair shipments
 *     (delete phantoms, split multi-piece into N rows under the same order_id,
 *     collapse duplicate tracking rows down to one). Guarded behind an
 *     explicit flag so it is only ever run deliberately.
 *
 * Sender derivation: the orders table has no `sender` column. We best-effort
 * resolve a sender per order by matching its `source_email_ids` against
 * `email_classifications.email_id → sender_email`. When no match is found the
 * sender is left null — `planOrderBackfill` handles null (falls through to the
 * known-physical check, else archive).
 */

import { supabase } from './supabase';
import {
  planOrderBackfill,
  planShipmentRepair,
  BackfillOrder,
  BackfillAction,
  RepairShipment,
  RepairPlan,
} from './backfill-tracker';

interface OrderRow {
  id: string;
  merchant_name: string | null;
  normalized_merchant: string | null;
  source_email_ids: string[] | null;
}

interface ShipmentRow {
  id: string;
  order_id: string;
  tracking_number: string | null;
  carrier: string | null;
  source_email_ids: string[] | null;
}

export interface BackfillResult {
  mode: 'dry-run' | 'apply';
  orders: {
    total: number;
    counts: { keep: number; hide: number; archive: number };
    sample: { keep: BackfillAction[]; hide: BackfillAction[]; archive: BackfillAction[] };
    plan: BackfillAction[];
  };
  shipments: {
    total: number;
    counts: { deleteEmpty: number; split: number; splitInto: number; collapseDupes: number };
    sample: {
      deleteEmpty: RepairPlan['deleteEmpty'];
      split: RepairPlan['split'];
      collapseDupes: RepairPlan['collapseDupes'];
    };
    plan: RepairPlan;
  };
  applied?: {
    ordersHidden: number;
    ordersArchived: number;
    shipmentsDeleted: number;
    shipmentsSplitSource: number;
    shipmentsSplitCreated: number;
    shipmentsCollapsedDropped: number;
  };
}

const SAMPLE_N = 5;

// ─── Fetch (read-only) ───────────────────────────────────────────────────────

async function fetchOrders(userId: string): Promise<OrderRow[]> {
  const { data, error } = await supabase
    .from('orders')
    .select('id, merchant_name, normalized_merchant, source_email_ids')
    .eq('user_id', userId);
  if (error) throw new Error(`fetch orders failed: ${error.message}`);
  return (data || []) as OrderRow[];
}

async function fetchShipments(userId: string): Promise<ShipmentRow[]> {
  // shipments has no user_id column — scope via the order FK join.
  const { data, error } = await supabase
    .from('shipments')
    .select('id, order_id, tracking_number, carrier, source_email_ids, orders!inner(user_id)')
    .eq('orders.user_id', userId);
  if (error) throw new Error(`fetch shipments failed: ${error.message}`);
  return (data || []).map((r: Record<string, unknown>) => ({
    id: r.id as string,
    order_id: r.order_id as string,
    tracking_number: (r.tracking_number as string | null) ?? null,
    carrier: (r.carrier as string | null) ?? null,
    source_email_ids: (r.source_email_ids as string[] | null) ?? null,
  }));
}

/**
 * Best-effort sender resolution. Build a message_id → sender_email map from
 * email_classifications for this user, then look up each order's first
 * source_email_id. Returns null when unknown (planner tolerates null).
 */
async function buildSenderMap(userId: string): Promise<Map<string, string>> {
  const { data, error } = await supabase
    .from('email_classifications')
    .select('email_id, sender_email')
    .eq('user_id', userId)
    .not('sender_email', 'is', null);
  if (error) throw new Error(`fetch email_classifications failed: ${error.message}`);
  const map = new Map<string, string>();
  for (const row of (data || []) as { email_id: string; sender_email: string | null }[]) {
    if (row.email_id && row.sender_email && !map.has(row.email_id)) {
      map.set(row.email_id, row.sender_email);
    }
  }
  return map;
}

function resolveSender(order: OrderRow, senderMap: Map<string, string>): string | null {
  for (const eid of order.source_email_ids ?? []) {
    const s = senderMap.get(eid);
    if (s) return s;
  }
  return null;
}

// ─── Apply (writes — only when apply=true) ───────────────────────────────────

async function applyOrderPlan(plan: BackfillAction[]): Promise<{ hidden: number; archived: number }> {
  let hidden = 0;
  let archived = 0;
  for (const a of plan) {
    if (a.action === 'keep') continue;
    const hidden_reason = a.action === 'archive' ? 'archived_history' : a.reason;
    const { error } = await supabase
      .from('orders')
      .update({ hidden: true, hidden_reason, updated_at: new Date().toISOString() })
      .eq('id', a.id);
    if (error) throw new Error(`hide/archive order ${a.id} failed: ${error.message}`);
    if (a.action === 'archive') archived++;
    else hidden++;
  }
  return { hidden, archived };
}

async function applyShipmentPlan(
  plan: RepairPlan,
  ships: ShipmentRow[],
): Promise<{ deleted: number; splitSource: number; splitCreated: number; collapsedDropped: number }> {
  const byId = new Map(ships.map(s => [s.id, s]));
  let deleted = 0;
  let splitSource = 0;
  let splitCreated = 0;
  let collapsedDropped = 0;

  // 1. Delete empty-tracking phantoms.
  for (const { id } of plan.deleteEmpty) {
    const { error } = await supabase.from('shipments').delete().eq('id', id);
    if (error) throw new Error(`delete empty shipment ${id} failed: ${error.message}`);
    deleted++;
  }

  // Seed the seen-set with all tracking numbers already present, so the
  // split (and cross-order shared shipments) converge to exactly one row
  // per distinct tracking number — idempotent against existing data.
  const { data: existingRows, error: exErr } = await supabase
    .from('shipments')
    .select('tracking_number');
  if (exErr) throw new Error(`fetch existing tracking numbers failed: ${exErr.message}`);
  const seen = new Set<string>(
    (existingRows ?? [])
      .map((r: { tracking_number: string | null }) => (r.tracking_number ?? '').trim())
      .filter((tn: string) => tn.length > 0),
  );

  // 2. Split multi-piece rows: insert one row per NEW piece (skip pieces that
  //    already exist anywhere), then delete the original blob row.
  for (const { id, into } of plan.split) {
    const src = byId.get(id);
    if (!src) continue;
    const newPieces = into.filter(tn => !seen.has(tn));
    if (newPieces.length > 0) {
      const rows = newPieces.map(tn => ({
        order_id: src.order_id,
        tracking_number: tn,
        carrier: src.carrier,
        status: 'label_created',
        source_email_ids: src.source_email_ids ?? [],
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }));
      const { error: insErr } = await supabase.from('shipments').insert(rows);
      if (insErr) throw new Error(`split insert for ${id} failed: ${insErr.message}`);
      for (const tn of newPieces) seen.add(tn);
      splitCreated += rows.length;
    }
    // Always delete the malformed blob source row (its pieces are now covered).
    const { error: delErr } = await supabase.from('shipments').delete().eq('id', id);
    if (delErr) throw new Error(`split delete of source ${id} failed: ${delErr.message}`);
    splitSource++;
  }

  // 3. Collapse duplicate tracking rows: keep the first, delete the rest.
  for (const { drop } of plan.collapseDupes) {
    for (const dropId of drop) {
      const { error } = await supabase.from('shipments').delete().eq('id', dropId);
      if (error) throw new Error(`collapse-dupe delete ${dropId} failed: ${error.message}`);
      collapsedDropped++;
    }
  }

  return { deleted, splitSource, splitCreated, collapsedDropped };
}

// ─── Public entrypoint ───────────────────────────────────────────────────────

export async function runBackfill(userId: string, apply: boolean): Promise<BackfillResult> {
  if (!userId) throw new Error('runBackfill: userId required');

  const [orderRows, shipRows, senderMap] = await Promise.all([
    fetchOrders(userId),
    fetchShipments(userId),
    buildSenderMap(userId),
  ]);

  // Build planner inputs.
  const backfillOrders: BackfillOrder[] = orderRows.map(o => ({
    id: o.id,
    merchant_name: o.merchant_name ?? '',
    normalized_merchant: (o.normalized_merchant ?? '').toLowerCase(),
    sender: resolveSender(o, senderMap),
  }));
  const repairShips: RepairShipment[] = shipRows.map(s => ({
    id: s.id,
    tracking_number: s.tracking_number ?? '',
  }));

  const orderPlan = planOrderBackfill(backfillOrders);
  const shipPlan = planShipmentRepair(repairShips);

  const orderCounts = { keep: 0, hide: 0, archive: 0 };
  for (const a of orderPlan) orderCounts[a.action]++;

  const splitInto = shipPlan.split.reduce((n, s) => n + s.into.length, 0);

  const result: BackfillResult = {
    mode: apply ? 'apply' : 'dry-run',
    orders: {
      total: orderRows.length,
      counts: orderCounts,
      sample: {
        keep: orderPlan.filter(a => a.action === 'keep').slice(0, SAMPLE_N),
        hide: orderPlan.filter(a => a.action === 'hide').slice(0, SAMPLE_N),
        archive: orderPlan.filter(a => a.action === 'archive').slice(0, SAMPLE_N),
      },
      plan: orderPlan,
    },
    shipments: {
      total: shipRows.length,
      counts: {
        deleteEmpty: shipPlan.deleteEmpty.length,
        split: shipPlan.split.length,
        splitInto,
        collapseDupes: shipPlan.collapseDupes.length,
      },
      sample: {
        deleteEmpty: shipPlan.deleteEmpty.slice(0, SAMPLE_N),
        split: shipPlan.split.slice(0, SAMPLE_N),
        collapseDupes: shipPlan.collapseDupes.slice(0, SAMPLE_N),
      },
      plan: shipPlan,
    },
  };

  if (apply) {
    const o = await applyOrderPlan(orderPlan);
    const s = await applyShipmentPlan(shipPlan, shipRows);
    result.applied = {
      ordersHidden: o.hidden,
      ordersArchived: o.archived,
      shipmentsDeleted: s.deleted,
      shipmentsSplitSource: s.splitSource,
      shipmentsSplitCreated: s.splitCreated,
      shipmentsCollapsedDropped: s.collapsedDropped,
    };
  }

  return result;
}
