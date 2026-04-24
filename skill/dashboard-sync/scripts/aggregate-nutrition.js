#!/usr/bin/env node
/**
 * aggregate-nutrition.js
 *
 * Computes a daily nutrition progress_summary for the current day and upserts
 * it to dashboard_records. Fills the gap the audit surfaced: meals are logged
 * but no running total/target card is maintained, so the iOS app's macro gauge
 * is either empty or stale.
 *
 * Run on a cron (every ~30 min during waking hours, or on-demand after each
 * meal log). Idempotent — each run computes and upserts a single row keyed by
 * (user_id, category='nutrition', type='progress_summary', date).
 *
 * Env:
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  (required; resolved by cli.js style env loader)
 *   PERCH_USER_ID                            (required)
 *   PERCH_TZ                                 (optional, defaults to Europe/Lisbon)
 *
 * Targets resolution (first match wins):
 *   1. users.preferences -> 'nutrition_targets'  (per-user)
 *   2. hardcoded fallback below                  (lets the script run before
 *      targets are provisioned; logs a warning).
 */
'use strict';

const path = require('path');
const fs = require('fs');
const os = require('os');

// ─── Env resolution (mirrors cli.js) ───────────────────────────────────────

function loadEnvFile(p) {
  if (!p || !fs.existsSync(p)) return false;
  for (const line of fs.readFileSync(p, 'utf8').split('\n')) {
    let t = line.trim();
    if (!t || t.startsWith('#')) continue;
    if (t.startsWith('export ')) t = t.slice('export '.length);
    const eq = t.indexOf('=');
    if (eq <= 0) continue;
    const k = t.slice(0, eq).trim();
    let v = t.slice(eq + 1).trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
    if (process.env[k] === undefined || process.env[k] === '') process.env[k] = v;
  }
  return true;
}
if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
  for (const p of [
    process.env.DASHBOARD_SYNC_ENV_FILE,
    path.join(os.homedir(), '.openclaw/secrets/dashboard-sync.env'),
    path.join(os.homedir(), '.openclaw/secrets/perch.env'),
    path.join(__dirname, '..', '.env'),
  ]) {
    if (loadEnvFile(p)) break;
  }
}

for (const key of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'PERCH_USER_ID']) {
  if (!process.env[key]) {
    console.error(`aggregate-nutrition: ${key} is required`);
    process.exit(2);
  }
}

const { supabase } = require('../dist/supabase.js');

const TZ = process.env.PERCH_TZ || 'Europe/Lisbon';
const USER_ID = process.env.PERCH_USER_ID;
const AGENT_ID = 'nutrition-aggregator';

// Profile-aware targets. The user's preferences can look like:
//   {
//     "nutrition_targets": {
//       "profiles": {
//         "training": { "calories": 2900, "protein": 190, "carbs": 350, "fat": 80 },
//         "pilates":  { "calories": 2700, "protein": 190, "carbs": 305, "fat": 80 },
//         "rest":     { "calories": 2500, "protein": 190, "carbs": 255, "fat": 80 }
//       },
//       "rules": [
//         { "if_event_contains": ["gym","training","pull","push","legs"], "profile": "training" },
//         { "if_event_contains": ["pilates"], "profile": "pilates" }
//       ],
//       "default_profile": "rest"
//     }
//   }
//
// For back-compat, a flat {calories, protein, carbs, fat} object at the root
// of nutrition_targets is still treated as a fixed target set (no calendar
// lookup, same behavior as before).
const DEFAULT_TARGETS_BY_PROFILE = {
  training: { calories: 2900, protein: 190, carbs: 350, fat: 80 },
  pilates:  { calories: 2700, protein: 190, carbs: 305, fat: 80 },
  rest:     { calories: 2500, protein: 190, carbs: 255, fat: 80 },
};
const DEFAULT_RULES = [
  { if_event_contains: ['gym', 'training', 'workout', 'pull day', 'push day', 'legs day', 'crossfit', 'weights', 'lift'], profile: 'training' },
  { if_event_contains: ['pilates', 'yoga', 'stretch'], profile: 'pilates' },
];
const DEFAULT_PROFILE = 'rest';
// Legacy flat default used only if user preferences look like the old flat
// shape AND are incomplete. Kept for safety; not exposed as a profile.
const LEGACY_FLAT_DEFAULTS = { calories: 2800, protein: 180, carbs: 320, fat: 90 };

// ─── Helpers ───────────────────────────────────────────────────────────────

/**
 * Get the ISO date (YYYY-MM-DD) for "today" in the user's TZ. Uses
 * Intl.DateTimeFormat so it works without timezone libs.
 */
function todayISODate() {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date());
  const y = parts.find(p => p.type === 'year').value;
  const m = parts.find(p => p.type === 'month').value;
  const d = parts.find(p => p.type === 'day').value;
  return `${y}-${m}-${d}`;
}

/**
 * Return [startUtc, endUtc] ISO strings for "today in user's TZ" converted to
 * UTC, for DB queries.
 */
function todayUtcBounds() {
  const iso = todayISODate();
  // Construct midnight in the user's TZ. We do this by formatting the local
  // Y-M-D + 00:00 and +24:00 as if they were in TZ; the result is parsed as a
  // *local* date but we'll correct by offsetting via the formatter.
  // Simpler: build a Date at noon UTC and offset by the TZ offset for that date.
  const todayMidnightLocal = new Date(`${iso}T00:00:00`);
  const offsetMs = getTZOffsetMs(todayMidnightLocal, TZ);
  const startUtc = new Date(todayMidnightLocal.getTime() - offsetMs);
  const endUtc = new Date(startUtc.getTime() + 24 * 3600 * 1000);
  return [startUtc.toISOString(), endUtc.toISOString()];
}

function getTZOffsetMs(dateLike, tz) {
  // Returns the offset in ms between the given instant and the same wall-clock
  // time interpreted in `tz`. Negative for TZ ahead of UTC.
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hourCycle: 'h23',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
  const parts = dtf.formatToParts(dateLike).reduce((a, p) => { a[p.type] = p.value; return a; }, {});
  const asUtc = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour, +parts.minute, +parts.second);
  return asUtc - dateLike.getTime();
}

async function loadTargets() {
  const { data, error } = await supabase
    .from('users')
    .select('preferences')
    .eq('id', USER_ID)
    .maybeSingle();
  if (error) {
    console.error(`aggregate-nutrition: users lookup failed: ${error.message}`);
    return resolveProfileFallback('defaults-on-error');
  }

  const nt = data?.preferences?.nutrition_targets;

  // Back-compat: flat {calories,protein,carbs,fat} at root → treat as fixed.
  if (nt && typeof nt === 'object' && typeof nt.calories === 'number' && !nt.profiles) {
    const n = (x, d) => (Number.isFinite(+x) ? +x : d);
    return {
      targets: {
        calories: n(nt.calories, LEGACY_FLAT_DEFAULTS.calories),
        protein: n(nt.protein, LEGACY_FLAT_DEFAULTS.protein),
        carbs: n(nt.carbs, LEGACY_FLAT_DEFAULTS.carbs),
        fat: n(nt.fat, LEGACY_FLAT_DEFAULTS.fat),
      },
      source: 'user-prefs-flat',
      profile: 'flat',
      matchedEvent: null,
    };
  }

  // Profile-aware path.
  const profiles = (nt && typeof nt === 'object' && nt.profiles && typeof nt.profiles === 'object')
    ? nt.profiles
    : DEFAULT_TARGETS_BY_PROFILE;
  const rules = Array.isArray(nt?.rules) ? nt.rules : DEFAULT_RULES;
  const defaultProfile = (typeof nt?.default_profile === 'string' && nt.default_profile in profiles)
    ? nt.default_profile
    : DEFAULT_PROFILE;

  const { profile, matchedEvent } = await pickProfileForToday(rules, profiles, defaultProfile);
  const raw = profiles[profile] ?? DEFAULT_TARGETS_BY_PROFILE[profile] ?? LEGACY_FLAT_DEFAULTS;
  const n = (x, d) => (Number.isFinite(+x) ? +x : d);
  return {
    targets: {
      calories: n(raw.calories, LEGACY_FLAT_DEFAULTS.calories),
      protein: n(raw.protein, LEGACY_FLAT_DEFAULTS.protein),
      carbs: n(raw.carbs, LEGACY_FLAT_DEFAULTS.carbs),
      fat: n(raw.fat, LEGACY_FLAT_DEFAULTS.fat),
    },
    source: nt ? 'user-prefs-profile' : 'defaults-profile',
    profile,
    matchedEvent,
  };
}

function resolveProfileFallback(source) {
  return {
    targets: { ...DEFAULT_TARGETS_BY_PROFILE[DEFAULT_PROFILE] },
    source,
    profile: DEFAULT_PROFILE,
    matchedEvent: null,
  };
}

async function pickProfileForToday(rules, profiles, defaultProfile) {
  const [startUtc, endUtc] = todayUtcBounds();
  // Read today's calendar events from dashboard_records (populated by
  // calendar_dashboard_sync.py). Match each event title against the rules
  // in order; first match wins. Fall back to defaultProfile.
  const { data, error } = await supabase
    .from('dashboard_records')
    .select('title, data, created_at')
    .eq('user_id', USER_ID)
    .eq('category', 'calendar')
    .eq('type', 'event')
    .gte('created_at', startUtc)
    .lt('created_at', endUtc);
  if (error) {
    console.error(`aggregate-nutrition: calendar lookup failed: ${error.message}`);
    return { profile: defaultProfile, matchedEvent: null };
  }
  const events = data || [];
  for (const rule of rules) {
    const needles = (rule.if_event_contains || []).map(s => String(s).toLowerCase());
    const profileName = rule.profile;
    if (!profileName || !(profileName in profiles || profileName in DEFAULT_TARGETS_BY_PROFILE)) continue;
    for (const ev of events) {
      const hay = `${ev.title || ''} ${(ev.data && (ev.data.notes || ev.data.location)) || ''}`.toLowerCase();
      if (needles.some(n => hay.includes(n))) {
        return { profile: profileName, matchedEvent: ev.title || '(untitled)' };
      }
    }
  }
  return { profile: defaultProfile, matchedEvent: null };
}

async function loadTodaysMeals() {
  const [startUtc, endUtc] = todayUtcBounds();
  const { data, error } = await supabase
    .from('dashboard_records')
    .select('id, title, data, created_at')
    .eq('user_id', USER_ID)
    .eq('category', 'nutrition')
    .eq('type', 'meal')
    .gte('created_at', startUtc)
    .lt('created_at', endUtc);
  if (error) {
    throw new Error(`meals query failed: ${error.message}`);
  }
  return data || [];
}

function sumMeals(meals) {
  const pick = (m, keys) => {
    const d = m.data || {};
    for (const k of keys) if (d[k] !== undefined && d[k] !== null) return +d[k] || 0;
    return 0;
  };
  const totals = { calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0 };
  for (const m of meals) {
    totals.calories += pick(m, ['calories']);
    totals.protein += pick(m, ['protein', 'protein_g']);
    totals.carbs += pick(m, ['carbs', 'carbs_g']);
    totals.fat += pick(m, ['fat', 'fat_g']);
    totals.fiber += pick(m, ['fiber', 'fiber_g']);
  }
  return totals;
}

async function upsertProgressSummary({ date, targets, totals, mealsCount, profile, matchedEvent }) {
  const remaining = {
    calories: targets.calories - totals.calories,
    protein: targets.protein - totals.protein,
    carbs: targets.carbs - totals.carbs,
    fat: targets.fat - totals.fat,
  };

  // NOTE on field naming: the iOS `MacrosData` decoder (Models/DataPayloads.swift)
  // expects `protein`, `protein_target`, `carbs`, `carbs_target`, `fat`,
  // `fat_target`, and `date`. We emit those as the primary fields so
  // `record.asMacros()` succeeds and `NutritionTargets.resolved(for:records:)`
  // (Models/NutritionModels.swift) picks up real targets in place of the
  // hardcoded 180/386/110 fallback the audit flagged.
  //
  // We ALSO emit descriptive `consumed_*_g` / `target_*_g` / `remaining_*_g`
  // mirrors for downstream tooling (Agent/SQL queries, dashboards) that may
  // want the more explicit names. Both stay in sync because they're derived
  // from the same totals in one place.
  const r1 = (x) => Math.round(x * 10) / 10;
  const payload = {
    agent_id: AGENT_ID,
    user_id: USER_ID,
    category: 'nutrition',
    type: 'progress_summary',
    title: `Nutrition progress — ${date}`,
    display_hint: 'macros_bar',
    pinned: false,
    data: {
      // iOS-decoder-compatible (MacrosData) keys
      date,
      protein: r1(totals.protein),
      protein_target: targets.protein,
      carbs: r1(totals.carbs),
      carbs_target: targets.carbs,
      fat: r1(totals.fat),
      fat_target: targets.fat,
      // Descriptive mirrors for operators / SQL views
      target_calories: targets.calories,
      target_protein_g: targets.protein,
      target_carbs_g: targets.carbs,
      target_fat_g: targets.fat,
      consumed_calories: r1(totals.calories),
      consumed_protein_g: r1(totals.protein),
      consumed_carbs_g: r1(totals.carbs),
      consumed_fat_g: r1(totals.fat),
      consumed_fiber_g: r1(totals.fiber),
      remaining_calories: r1(remaining.calories),
      remaining_protein_g: r1(remaining.protein),
      remaining_carbs_g: r1(remaining.carbs),
      remaining_fat_g: r1(remaining.fat),
      meals_logged: mealsCount,
      profile: profile || null,
      matched_event: matchedEvent || null,
      aggregated_at: new Date().toISOString(),
    },
  };

  // Upsert semantics: one progress_summary per (user, date).
  // We search first, then update or insert, because dashboard_records lacks a
  // natural unique constraint on (user_id, category, type, data->>'date').
  const { data: existing, error: findErr } = await supabase
    .from('dashboard_records')
    .select('id')
    .eq('user_id', USER_ID)
    .eq('category', 'nutrition')
    .eq('type', 'progress_summary')
    .filter('data->>date', 'eq', date)
    .maybeSingle();
  if (findErr) throw new Error(`find failed: ${findErr.message}`);

  if (existing?.id) {
    const { error: updErr } = await supabase
      .from('dashboard_records')
      .update({ data: payload.data, updated_at: new Date().toISOString() })
      .eq('id', existing.id);
    if (updErr) throw new Error(`update failed: ${updErr.message}`);
    return { id: existing.id, action: 'updated' };
  }
  const { data: inserted, error: insErr } = await supabase
    .from('dashboard_records')
    .insert([payload])
    .select('id')
    .single();
  if (insErr) throw new Error(`insert failed: ${insErr.message}`);
  return { id: inserted.id, action: 'created' };
}

async function recordRun(runId, status, summary, errorDetail) {
  try {
    if (runId) {
      await supabase.from('agent_runs')
        .update({
          ended_at: new Date().toISOString(),
          status,
          summary: summary || null,
          error_detail: errorDetail || null,
        })
        .eq('id', runId);
    }
  } catch (_) {
    // agent_runs is observability only — never let it break the pipeline.
  }
}

async function startRun() {
  try {
    const { data } = await supabase.from('agent_runs')
      .insert([{ agent_id: AGENT_ID, run_type: 'aggregate', status: 'running' }])
      .select('id')
      .single();
    return data?.id || null;
  } catch (_) {
    return null;
  }
}

// ─── Main ──────────────────────────────────────────────────────────────────

(async () => {
  const runId = await startRun();
  try {
    const date = todayISODate();
    const { targets, source: targetsSource, profile, matchedEvent } = await loadTargets();
    const meals = await loadTodaysMeals();
    const totals = sumMeals(meals);
    const upsert = await upsertProgressSummary({
      date, targets, totals, mealsCount: meals.length, profile, matchedEvent,
    });

    const summary = {
      date,
      meals_logged: meals.length,
      consumed_calories: Math.round(totals.calories),
      profile,
      matched_event: matchedEvent,
      targets_source: targetsSource,
      action: upsert.action,
      progress_summary_id: upsert.id,
    };
    await recordRun(runId, 'ok', summary, null);
    console.log(JSON.stringify(summary, null, 2));
    process.exit(0);
  } catch (e) {
    const detail = (e && e.message) || String(e);
    await recordRun(runId, 'error', null, detail);
    console.error(`aggregate-nutrition failed: ${detail}`);
    process.exit(1);
  }
})();
