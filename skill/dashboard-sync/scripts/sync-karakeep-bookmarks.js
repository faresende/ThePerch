#!/usr/bin/env node
/**
 * sync-karakeep-bookmarks.js
 *
 * Pulls recent Karakeep bookmarks and upserts them as dashboard_records
 * so the iOS app's Paperless tab (category=bookmarks) stays current.
 *
 * Replaces the dead pipeline from Archie's malformed JSON writer (the
 * file at ~/.openclaw/agents/archie/data/karakeep_bookmarks.json has
 * un-escaped double-quotes inside Instagram caption titles, breaking any
 * downstream reader).
 *
 * Why Node and not Python: the rest of dashboard-sync is Node; the same
 * env-resolution + Supabase client pattern applies. Paperless has its
 * own Python script we leave alone for now.
 *
 * Env:
 *   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  (required; cli.js-style resolution)
 *   PERCH_USER_ID                            (required)
 *   KARAKEEP_BASE_URL                        (required)
 *   KARAKEEP_TOKEN                           (required)
 *   KARAKEEP_SYNC_LIMIT                      (optional; default 100)
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
  ]) { if (loadEnvFile(p)) break; }
}

for (const key of ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'PERCH_USER_ID', 'KARAKEEP_BASE_URL', 'KARAKEEP_TOKEN']) {
  if (!process.env[key]) {
    console.error(`sync-karakeep-bookmarks: ${key} is required`);
    process.exit(2);
  }
}

const { supabase } = require('../dist/supabase.js');

const USER_ID = process.env.PERCH_USER_ID;
const AGENT_ID = 'archie';
const KARAKEEP_BASE_URL = process.env.KARAKEEP_BASE_URL.replace(/\/$/, '');
const KARAKEEP_TOKEN = process.env.KARAKEEP_TOKEN;
const SYNC_LIMIT = Number(process.env.KARAKEEP_SYNC_LIMIT || 100);

// ─── Karakeep fetch ────────────────────────────────────────────────────────

async function fetchKarakeepBookmarks(limit) {
  const url = `${KARAKEEP_BASE_URL}/v1/bookmarks?limit=${encodeURIComponent(String(limit))}`;
  const resp = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${KARAKEEP_TOKEN}`,
      'Accept': 'application/json',
    },
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Karakeep fetch failed ${resp.status}: ${text.slice(0, 500)}`);
  }
  const json = await resp.json();
  return Array.isArray(json?.bookmarks) ? json.bookmarks : [];
}

function shapeForDashboard(bookmark) {
  // Pull a readable title; Karakeep often leaves the top-level null and puts
  // the real one inside `content`.
  const content = bookmark.content ?? {};
  const url = content.url || null;
  if (!url) return null; // skip non-link bookmarks for now

  const title = bookmark.title || content.title || content.url || 'Untitled';
  const description = content.description || bookmark.summary || null;
  const imageUrl = content.imageUrl || null;
  const favicon = content.favicon || null;
  const domain = (() => {
    try { return new URL(url).hostname; } catch { return null; }
  })();
  const tags = Array.isArray(bookmark.tags)
    ? bookmark.tags.map(t => (typeof t === 'string' ? t : (t?.name || ''))).filter(Boolean)
    : [];

  const status = (() => {
    switch (content.crawlStatus) {
      case 'success': return 'processed';
      case 'pending': return 'pending';
      case 'failed':  return 'failed';
      default:        return 'processing';
    }
  })();

  return {
    // iOS KarakeepBookmark-compatible shape. The BookmarksView Paperless
    // tab decodes records.data as this object.
    id: bookmark.id,
    karakeep_id: bookmark.id,
    source: 'karakeep',
    url,
    title,
    description,
    tags,
    domain,
    image_url: imageUrl,
    favicon,
    reading_time_minutes: null,
    status,
    archived: !!bookmark.archived,
    favourited: !!bookmark.favourited,
    created_at: bookmark.createdAt,
    updated_at: bookmark.modifiedAt || bookmark.createdAt,
    publisher: content.publisher || null,
    author: content.author || null,
  };
}

// ─── Upsert strategy ───────────────────────────────────────────────────────

async function upsertBookmark(data) {
  const title = data.title;
  // Use the Karakeep id as the dedup key inside dashboard_records.data.
  const { data: existing, error: findErr } = await supabase
    .from('dashboard_records')
    .select('id')
    .eq('user_id', USER_ID)
    .eq('category', 'bookmarks')
    .eq('type', 'bookmark')
    .filter('data->>karakeep_id', 'eq', data.karakeep_id)
    .maybeSingle();
  if (findErr) throw new Error(`find: ${findErr.message}`);

  const now = new Date().toISOString();
  if (existing?.id) {
    const { error } = await supabase
      .from('dashboard_records')
      .update({ data, title, updated_at: now })
      .eq('id', existing.id);
    if (error) throw new Error(`update: ${error.message}`);
    return { id: existing.id, action: 'updated' };
  }
  const { data: inserted, error } = await supabase
    .from('dashboard_records')
    .insert([{
      agent_id: AGENT_ID,
      user_id: USER_ID,
      category: 'bookmarks',
      type: 'bookmark',
      title,
      display_hint: 'bookmark',
      pinned: false,
      data,
    }])
    .select('id')
    .single();
  if (error) throw new Error(`insert: ${error.message}`);
  return { id: inserted.id, action: 'created' };
}

// ─── agent_runs brackets ───────────────────────────────────────────────────

async function startRun() {
  try {
    const { data } = await supabase.from('agent_runs')
      .insert([{ agent_id: AGENT_ID, run_type: 'sync', status: 'running' }])
      .select('id').single();
    return data?.id || null;
  } catch (_) { return null; }
}
async function endRun(runId, status, summary, errorDetail) {
  if (!runId) return;
  try {
    await supabase.from('agent_runs').update({
      ended_at: new Date().toISOString(),
      status,
      summary: summary || null,
      error_detail: errorDetail || null,
    }).eq('id', runId);
  } catch (_) { /* best effort */ }
}

// ─── Main ──────────────────────────────────────────────────────────────────

(async () => {
  const runId = await startRun();
  try {
    const raws = await fetchKarakeepBookmarks(SYNC_LIMIT);
    let created = 0, updated = 0, skipped = 0;
    for (const raw of raws) {
      const shaped = shapeForDashboard(raw);
      if (!shaped) { skipped++; continue; }
      const result = await upsertBookmark(shaped);
      if (result.action === 'created') created++;
      else if (result.action === 'updated') updated++;
    }
    const summary = { fetched: raws.length, created, updated, skipped };
    await endRun(runId, 'ok', summary, null);
    console.log(JSON.stringify(summary, null, 2));
    process.exit(0);
  } catch (e) {
    const detail = (e && e.message) || String(e);
    await endRun(runId, 'error', null, detail);
    console.error(`sync-karakeep-bookmarks failed: ${detail}`);
    process.exit(1);
  }
})();
