#!/usr/bin/env node
/**
 * One-shot backfill: re-fetch the source carrier email for each
 * existing undelivered shipment, run it through extract-eta, and
 * write any ETA we find via the same resolveETAUpdate path the
 * scanner uses on new emails.
 *
 * Targets the legacy gap: shipments created before the ETA
 * extractor existed. Their carrier emails almost always have
 * "Expected delivery: <date>" lines we'd extract today; this
 * script captures that retroactively.
 *
 * Run with perch.env sourced.
 */
const { execSync } = require('child_process');

// Resolve dependencies from the dashboard-sync skill installation.
// Override via SKILL_PATH env if your openclaw layout is non-default.
const SKILL_PATH = process.env.SKILL_PATH
  || `${process.env.HOME}/.openclaw/skills/dashboard-sync`;
const { createClient } = require(`${SKILL_PATH}/node_modules/@supabase/supabase-js`);
const { extractETACandidates, pickETA } = require(`${SKILL_PATH}/dist/extract-eta`);
const { resolveETAUpdate } = require(`${SKILL_PATH}/dist/resolve-eta`);

const SESSION_URL = 'https://api.fastmail.com/jmap/session';

function getJmapToken() {
  if (process.env.FASTMAIL_API_TOKEN?.trim()) return process.env.FASTMAIL_API_TOKEN.trim();
  return execSync(
    "security find-generic-password -a 'fastmail-jmap' -s 'fastmail-jmap-token' -w",
    { encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] },
  ).trim();
}

async function getJmapSession() {
  const token = getJmapToken();
  if (!token) throw new Error('No JMAP token (env or keychain)');
  const r = await fetch(SESSION_URL, { headers: { Authorization: `Bearer ${token}` } });
  if (!r.ok) throw new Error(`JMAP session failed: ${r.status}`);
  const j = await r.json();
  const accountId = Object.keys(j.accounts)[0];
  return { apiUrl: j.apiUrl, accountId, token };
}

async function fetchEmail(session, emailId) {
  const r = await fetch(session.apiUrl, {
    method: 'POST',
    headers: { Authorization: `Bearer ${session.token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      using: ['urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:mail'],
      methodCalls: [[
        'Email/get',
        {
          accountId: session.accountId,
          ids: [emailId],
          properties: ['subject', 'textBody', 'bodyValues'],
          fetchTextBodyValues: true,
        },
        '0',
      ]],
    }),
  });
  if (!r.ok) return null;
  const j = await r.json();
  const email = j?.methodResponses?.[0]?.[1]?.list?.[0];
  if (!email) return null;
  const subject = email.subject ?? '';
  // Concatenate all text body parts
  let body = '';
  for (const part of email.textBody ?? []) {
    const v = email.bodyValues?.[part.partId]?.value;
    if (v) body += v + '\n';
  }
  return { subject, body };
}

async function main() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) { console.error('Missing SUPABASE_URL / SERVICE_ROLE_KEY'); process.exit(2); }

  const sb = createClient(url, key);
  const session = await getJmapSession();

  // Pull every undelivered shipment with its source_email_ids + current eta state.
  const { data: ships, error } = await sb
    .from('shipments')
    .select('id, tracking_number, carrier, source_email_ids, eta_at, eta_source, eta_recorded_at')
    .is('delivered_at', null);
  if (error) { console.error(error); process.exit(1); }

  console.log(`Backfilling ETAs for ${ships.length} undelivered shipments…`);

  let attempted = 0;
  let extracted = 0;
  let written = 0;
  let skipped = 0;

  for (const ship of ships) {
    const emailIds = ship.source_email_ids ?? [];
    if (emailIds.length === 0) { skipped++; continue; }

    for (const eid of emailIds) {
      attempted++;
      let email;
      try {
        email = await fetchEmail(session, eid);
      } catch (e) {
        console.log(`  ${ship.tracking_number} ${eid}: fetch err ${e.message}`);
        continue;
      }
      if (!email) {
        console.log(`  ${ship.tracking_number} ${eid}: not found in JMAP`);
        continue;
      }

      const candidates = extractETACandidates(email.subject, email.body);
      const winner = pickETA(candidates, new Date());
      if (!winner) continue;
      extracted++;

      const now = new Date();
      const resolved = resolveETAUpdate(
        {
          eta_at: ship.eta_at ? new Date(ship.eta_at) : null,
          eta_source: ship.eta_source ?? null,
          eta_recorded_at: ship.eta_recorded_at ? new Date(ship.eta_recorded_at) : null,
        },
        { eta_at: winner.date, eta_source: 'carrier_email', eta_recorded_at: now },
      );
      if (!resolved) {
        console.log(`  ${ship.tracking_number}: extracted ${winner.date.toISOString().slice(0, 10)} but resolver said skip (existing higher priority)`);
        break;
      }

      const { error: upErr } = await sb
        .from('shipments')
        .update({
          eta_at: resolved.eta_at.toISOString(),
          eta_source: resolved.eta_source,
          eta_recorded_at: resolved.eta_recorded_at.toISOString(),
          updated_at: now.toISOString(),
        })
        .eq('id', ship.id);
      if (upErr) { console.log(`  ${ship.tracking_number}: update err ${upErr.message}`); continue; }
      console.log(`  ${ship.tracking_number} (${ship.carrier ?? '?'}) → ${resolved.eta_at.toISOString().slice(0, 10)} from ${winner.matchedText.trim().slice(0, 60)}`);
      written++;
      break;  // one ETA per shipment is enough
    }
  }

  console.log(`---attempted=${attempted}  extracted=${extracted}  written=${written}  skipped(no source emails)=${skipped}`);
}

main().catch(e => { console.error(e); process.exit(1); });
