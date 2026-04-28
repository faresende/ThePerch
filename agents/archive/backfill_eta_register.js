#!/usr/bin/env node
/**
 * One-shot backfill: register every undelivered shipment with 17track.
 * Catches legacy shipments that were created before the autopilot
 * routinely registered tracking numbers, plus any that slipped through.
 *
 * After registration, the next 17track poll cycle will return data
 * (status, ETAs when published) for these shipments. Re-running
 * pollShipments via cli.js immediately after this script gives a
 * faster end-to-end refresh.
 *
 * Run from a shell with perch.env sourced.
 */
// Resolve dependencies from the dashboard-sync skill installation.
// Override via SKILL_PATH env if your openclaw layout is non-default.
const SKILL_PATH = process.env.SKILL_PATH
  || `${process.env.HOME}/.openclaw/skills/dashboard-sync`;
const { createClient } = require(`${SKILL_PATH}/node_modules/@supabase/supabase-js`);

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function main() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const apiKey = process.env.SEVENTEEN_TRACK_API_KEY;
  if (!url || !key || !apiKey) {
    console.error('Missing env: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / SEVENTEEN_TRACK_API_KEY');
    process.exit(2);
  }

  const c = createClient(url, key);
  const { data: shipments, error } = await c
    .from('shipments')
    .select('tracking_number, carrier')
    .is('delivered_at', null);
  if (error) { console.error(error); process.exit(1); }

  const items = shipments
    .filter(s => s.tracking_number)
    .map(s => ({ number: s.tracking_number, ...(s.carrier ? { carrier: s.carrier } : {}) }));

  console.log(`Found ${items.length} undelivered shipments. Registering in batches of 30 with 17track…`);

  let totalAccepted = 0;
  let totalRejected = 0;
  for (let i = 0; i < items.length; i += 30) {
    const batch = items.slice(i, i + 30);
    const r = await fetch('https://api.17track.net/track/v2.2/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', '17token': apiKey },
      body: JSON.stringify(batch),
    });
    const text = await r.text();
    let j;
    try { j = JSON.parse(text); } catch (e) { console.log(`batch ${i}: parse err: ${text.slice(0, 100)}`); continue; }
    const acc = (j.data?.accepted || []).length;
    const rej = (j.data?.rejected || []).length;
    totalAccepted += acc;
    totalRejected += rej;
    console.log(`  batch ${i}-${i + batch.length - 1}: accepted=${acc} rejected=${rej}`);
    // 17track quietly accepts already-registered numbers as "rejected"
    // with a "number already exists" error — that's expected and OK.
    await sleep(500);
  }
  console.log(`---total accepted=${totalAccepted} rejected=${totalRejected} (note: rejected typically = "already registered")`);
}

main().catch(e => { console.error(e); process.exit(1); });
