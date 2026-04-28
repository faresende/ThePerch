#!/usr/bin/env node
/**
 * One-shot script to swap your real data for plausible demo data,
 * for taking landing-page / README screenshots.
 *
 * Workflow:
 *   1. node seed-demo-data.js snapshot     — saves real data to .demo-snapshot.json
 *   2. node seed-demo-data.js seed         — replaces real data with demo set
 *   3. (take screenshots)
 *   4. node seed-demo-data.js restore      — replaces demo data with snapshot
 *
 * Touched tables (in order): orders, shipments, order_items,
 * health_metrics, insights, dashboard_records (just the deliveries
 * + nutrition slices), order_corrections.
 *
 * The snapshot file is in .gitignore by name (.demo-snapshot.json) —
 * never commit it. It contains your real data.
 *
 * Run with perch.env sourced (uses SERVICE_ROLE so RLS doesn't block).
 */

const fs = require('fs');
const path = require('path');

const SKILL_PATH = process.env.SKILL_PATH
  || `${process.env.HOME}/.openclaw/skills/dashboard-sync`;
const { createClient } = require(`${SKILL_PATH}/node_modules/@supabase/supabase-js`);

const SNAPSHOT_FILE = path.join(__dirname, '.demo-snapshot.json');

const TABLES = [
  // Order matters for restore: parents before children, but for
  // delete we go children-first. Each entry: { name, fk_to_user }
  { name: 'order_corrections', userScoped: true },
  { name: 'order_items', userScoped: false },     // FK via order_id
  { name: 'shipments', userScoped: false },        // FK via order_id
  { name: 'orders', userScoped: true },
  { name: 'health_metrics', userScoped: true },
  { name: 'insights', userScoped: true },
  // Nutrition cards on Today read from dashboard_records, not health_metrics.
  // Snapshot/restore the user's nutrition slice only — leave bookmarks,
  // workouts, calendar agent-fed records, etc. alone.
  { name: 'dashboard_records', userScoped: true, filter: { category: 'nutrition' } },
];

async function main() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const userId = process.env.PERCH_USER_ID;
  if (!url || !key || !userId) {
    console.error('Missing SUPABASE_URL / SERVICE_ROLE_KEY / PERCH_USER_ID');
    process.exit(2);
  }
  const sb = createClient(url, key);

  const cmd = process.argv[2];
  switch (cmd) {
    case 'snapshot': await snapshot(sb, userId); break;
    case 'seed':     await seed(sb, userId); break;
    case 'restore':  await restore(sb, userId); break;
    default:
      console.error('Usage: seed-demo-data.js snapshot|seed|restore');
      process.exit(2);
  }
}

// ─── Snapshot ────────────────────────────────────────────────────────

async function snapshot(sb, userId) {
  console.log('Snapshotting current data → .demo-snapshot.json');
  const out = {};
  for (const t of TABLES) {
    let q = sb.from(t.name).select('*');
    if (t.userScoped) q = q.eq('user_id', userId);
    // Per-table optional filter (e.g. dashboard_records narrowed
    // to category=nutrition so we don't blow away unrelated rows).
    if (t.filter) {
      for (const [col, val] of Object.entries(t.filter)) {
        q = q.eq(col, val);
      }
    }
    const { data, error } = await q;
    if (error) { console.error(`snapshot ${t.name}:`, error); process.exit(1); }
    out[t.name] = data || [];
    const filterDesc = t.filter ? ` (${Object.entries(t.filter).map(([k,v]) => `${k}=${v}`).join(',')})` : '';
    console.log(`  ${t.name}${filterDesc}: ${data.length} rows`);
  }
  fs.writeFileSync(SNAPSHOT_FILE, JSON.stringify(out, null, 2));
  console.log(`✓ snapshot saved (${(JSON.stringify(out).length / 1024).toFixed(1)} KB)`);
  console.log('  Run `seed-demo-data.js seed` next.');
}

// ─── Seed ────────────────────────────────────────────────────────────

async function seed(sb, userId) {
  // Always snapshot first — never trust a pre-existing file. The
  // earlier behavior (require a snapshot, but trust whatever it
  // contained) was the bug that lost nutrition data: a stale
  // snapshot from before TABLES list got extended would silently
  // miss the new tables, restore would wipe-then-not-reinsert.
  // Now: snapshot is always fresh at seed time, capturing exactly
  // the tables the wipe will touch.
  console.log('Auto-snapshotting current data BEFORE wipe…');
  await snapshot(sb, userId);
  console.log('Now seeding demo data…');
  await wipe(sb, userId);
  await insertDemo(sb, userId);
  console.log('✓ demo data seeded. Take your screenshots, then run `seed-demo-data.js restore`.');
}

// ─── Restore ─────────────────────────────────────────────────────────

async function restore(sb, userId) {
  if (!fs.existsSync(SNAPSHOT_FILE)) {
    console.error(`No snapshot found at ${SNAPSHOT_FILE}. Cannot restore.`);
    process.exit(1);
  }
  const snap = JSON.parse(fs.readFileSync(SNAPSHOT_FILE, 'utf-8'));
  console.log('Restoring real data from snapshot…');
  await wipe(sb, userId);
  // Insert in reverse-FK order: parents (orders, health_metrics, insights) first,
  // then children (shipments, items, corrections). dashboard_records last
  // because they're independent (no FK to orders).
  const order = ['orders', 'shipments', 'order_items', 'health_metrics', 'insights', 'order_corrections', 'dashboard_records'];
  for (const tname of order) {
    const rows = snap[tname];
    if (!rows || rows.length === 0) continue;
    // Chunk to keep payload under PostgREST default limits.
    for (let i = 0; i < rows.length; i += 200) {
      const chunk = rows.slice(i, i + 200);
      const { error } = await sb.from(tname).insert(chunk);
      if (error) { console.error(`restore ${tname}:`, error); process.exit(1); }
    }
    console.log(`  ${tname}: ${rows.length} rows`);
  }
  console.log('✓ real data restored.');
  console.log('  You may delete .demo-snapshot.json now if you don\'t want it lying around.');
}

// ─── Wipe ────────────────────────────────────────────────────────────

async function wipe(sb, userId) {
  // Children first to avoid FK violations.
  // Note: for child tables without user_id, we fetch the user's orders
  // first and delete by order_id to scope the wipe.
  const { data: ourOrders } = await sb
    .from('orders').select('id').eq('user_id', userId);
  const ourOrderIds = (ourOrders || []).map(o => o.id);

  // Children of orders
  if (ourOrderIds.length > 0) {
    await sb.from('order_corrections').delete().eq('user_id', userId);
    await sb.from('order_items').delete().in('order_id', ourOrderIds);
    await sb.from('shipments').delete().in('order_id', ourOrderIds);
  }
  // User-scoped parents
  await sb.from('orders').delete().eq('user_id', userId);
  await sb.from('health_metrics').delete().eq('user_id', userId);
  await sb.from('insights').delete().eq('user_id', userId);
  // Nutrition slice of dashboard_records ONLY (leave bookmarks,
  // workouts, calendar, travel, etc. alone — those are real-data
  // sources we don't want to wipe).
  await sb.from('dashboard_records')
    .delete()
    .eq('user_id', userId)
    .eq('category', 'nutrition');
}

// ─── Demo content ────────────────────────────────────────────────────

function isoDateDaysAgo(days) {
  const d = new Date(Date.now() - days * 86400 * 1000);
  return d.toISOString();
}
function isoTodayAt(hours) {
  const d = new Date();
  d.setHours(hours, 0, 0, 0);
  return d.toISOString();
}

async function insertDemo(sb, userId) {
  // 1) Orders + shipments — a balanced mix for screenshots.
  const orders = [
    {
      id: '11111111-1111-1111-1111-111111111111',
      user_id: userId,
      merchant_name: 'Hardgraft',
      normalized_merchant: 'hardgraft',
      order_number: 'HG-2487',
      order_date: isoDateDaysAgo(3),
      total_amount: 287.00,
      currency: 'EUR',
      status: 'shipped',
      source_email_ids: ['demo-hg-1'],
      confidence_score: 0.92,
    },
    {
      id: '22222222-2222-2222-2222-222222222222',
      user_id: userId,
      merchant_name: 'Body & Fit',
      normalized_merchant: 'body-and-fit',
      order_number: 'BF-991045',
      order_date: isoDateDaysAgo(2),
      total_amount: 64.50,
      currency: 'EUR',
      status: 'in_transit',
      source_email_ids: ['demo-bf-1'],
      confidence_score: 0.88,
    },
    {
      id: '33333333-3333-3333-3333-333333333333',
      user_id: userId,
      merchant_name: 'Topfoams',
      normalized_merchant: 'topfoams',
      order_number: 'TF-7733',
      order_date: isoDateDaysAgo(8),
      total_amount: 412.99,
      currency: 'EUR',
      status: 'shipped',
      source_email_ids: ['demo-tf-1'],
      confidence_score: 0.94,
    },
  ];
  await sb.from('orders').insert(orders);

  const shipments = [
    {
      order_id: '11111111-1111-1111-1111-111111111111',
      tracking_number: 'JD2089-DEMO-HG',
      carrier: 'DHL',
      tracking_url: 'https://www.dhl.com/tracking',
      seventeen_track_id: null,
      status: 'in_transit',
      latest_checkpoint: 'In transit · Frankfurt',
      shipped_at: isoDateDaysAgo(2),
      delivered_at: null,
      source_email_ids: ['demo-hg-ship-1'],
      confidence_score: 0.95,
      eta_at: isoDateDaysAgo(-2),       // 2 days from now
      eta_source: '17track',
      eta_recorded_at: isoDateDaysAgo(0),
    },
    {
      order_id: '22222222-2222-2222-2222-222222222222',
      tracking_number: '1Z2X4-DEMO-BF',
      carrier: 'UPS',
      tracking_url: 'https://www.ups.com/track',
      seventeen_track_id: null,
      status: 'in_transit',
      latest_checkpoint: 'Out for delivery',
      shipped_at: isoDateDaysAgo(1),
      delivered_at: null,
      source_email_ids: ['demo-bf-ship-1'],
      confidence_score: 0.91,
      eta_at: isoDateDaysAgo(0),         // today
      eta_source: '17track',
      eta_recorded_at: isoDateDaysAgo(0),
    },
    {
      order_id: '33333333-3333-3333-3333-333333333333',
      tracking_number: '00340-DEMO-TF',
      carrier: 'DHL',
      tracking_url: 'https://www.dhl.com/tracking',
      seventeen_track_id: null,
      status: 'in_transit',
      latest_checkpoint: 'Customs cleared',
      shipped_at: isoDateDaysAgo(4),
      delivered_at: null,
      source_email_ids: ['demo-tf-ship-1'],
      confidence_score: 0.93,
      eta_at: isoDateDaysAgo(-4),        // 4 days from now
      eta_source: 'carrier_email',
      eta_recorded_at: isoDateDaysAgo(3),
    },
  ];
  await sb.from('shipments').insert(shipments);

  // 2) Health metrics — last 7 days of sleep + body comp
  const metrics = [];
  for (let i = 0; i < 7; i++) {
    const day = isoDateDaysAgo(i);
    // Sleep duration: realistic noise around 6.5h with one bad night
    const sleepMin = i === 1 ? 240 : (380 + Math.floor(Math.random() * 80));
    metrics.push({
      user_id: userId, metric: 'sleep_duration_min', value: sleepMin, unit: 'min',
      source: '8sleep', source_id: `demo-sleep-${i}`, measured_at: day, details: null,
    });
    metrics.push({
      user_id: userId, metric: 'sleep_score', value: 60 + Math.floor(Math.random() * 30), unit: '',
      source: '8sleep', source_id: `demo-score-${i}`, measured_at: day, details: null,
    });
    metrics.push({
      user_id: userId, metric: 'hrv_rmssd_ms', value: 30 + Math.floor(Math.random() * 25), unit: 'ms',
      source: '8sleep', source_id: `demo-hrv-${i}`, measured_at: day, details: null,
    });
    metrics.push({
      user_id: userId, metric: 'resting_heart_rate_bpm', value: 50 + Math.floor(Math.random() * 8), unit: 'bpm',
      source: '8sleep', source_id: `demo-rhr-${i}`, measured_at: day, details: null,
    });
  }
  // Body comp — one weigh-in 4 days ago
  metrics.push(
    { user_id: userId, metric: 'weight_kg', value: 78.4, unit: 'kg', source: 'withings', source_id: 'demo-wt-1', measured_at: isoDateDaysAgo(4), details: null },
    { user_id: userId, metric: 'body_fat_pct', value: 18.2, unit: '%', source: 'withings', source_id: 'demo-bf-1', measured_at: isoDateDaysAgo(4), details: null },
    { user_id: userId, metric: 'fat_mass_kg', value: 14.3, unit: 'kg', source: 'withings', source_id: 'demo-fat-1', measured_at: isoDateDaysAgo(4), details: null },
    { user_id: userId, metric: 'muscle_mass_kg', value: 60.8, unit: 'kg', source: 'withings', source_id: 'demo-mus-1', measured_at: isoDateDaysAgo(4), details: null },
  );
  await sb.from('health_metrics').insert(metrics);

  // 3) BioChecha insight for today
  await sb.from('insights').insert([{
    user_id: userId,
    agent_id: 'biochecha',
    insight_type: 'daily_health',
    title: null,
    body: "Sleep dropped to less than half what you usually pull, while protein's lagged target two days running. Body's finally got something to say about the load. Today's a candidate for recovery, not volume.",
    data: { model: 'gpt-4o-mini', data_window_days: 7 },
    source_refs: null,
    valid_for_date: new Date().toISOString().slice(0, 10),
    pinned: false,
  }]);

  // 4) Nutrition records for today — feeds the Nutrition card on Today.
  // The card reads dashboard_records (category=nutrition, type=meal) and
  // sums calories/protein/carbs/fat. Three plausible meals + a snack so
  // the macro bars show meaningful progress (not maxed, not empty).
  const todayMorning = isoTodayAt(8);
  const todayLunch = isoTodayAt(13);
  const todaySnack = isoTodayAt(16);
  const meals = [
    {
      user_id: userId,
      type: 'meal',
      category: 'nutrition',
      title: 'Breakfast — oats, berries, yogurt',
      data: {
        calories: 420,
        protein: 22,
        carbs: 58,
        fat: 11,
        meal_time: todayMorning,
      },
      created_at: todayMorning,
    },
    {
      user_id: userId,
      type: 'meal',
      category: 'nutrition',
      title: 'Lunch — grilled chicken bowl',
      data: {
        calories: 640,
        protein: 48,
        carbs: 62,
        fat: 18,
        meal_time: todayLunch,
      },
      created_at: todayLunch,
    },
    {
      user_id: userId,
      type: 'meal',
      category: 'nutrition',
      title: 'Snack — apple + almond butter',
      data: {
        calories: 240,
        protein: 7,
        carbs: 28,
        fat: 14,
        meal_time: todaySnack,
      },
      created_at: todaySnack,
    },
  ];
  await sb.from('dashboard_records').insert(meals);

  console.log(`  orders: ${orders.length}, shipments: ${shipments.length}`);
  console.log(`  health_metrics: ${metrics.length}, insights: 1, meals: ${meals.length}`);
}

main().catch(e => { console.error(e); process.exit(1); });
