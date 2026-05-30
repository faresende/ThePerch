#!/usr/bin/env node
/**
 * CLI wrapper for dashboard-sync skill.
 *
 * Env resolution order (first match wins):
 *   1. caller's process.env  (if SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are both set, no file is loaded)
 *   2. DASHBOARD_SYNC_ENV_FILE env var pointing at a file
 *   3. ~/.openclaw/secrets/dashboard-sync.env
 *   4. ~/.openclaw/secrets/perch.env
 *   5. ./.env next to cli.js  (bare-clone fallback; also what the repo ships with)
 *
 * Usage:
 *   node cli.js heartbeat --agent_id main --user_id UUID [--display_name X] [--emoji ⚡] [--model X] [--is_active true]
 *   node cli.js push --agent_id X --user_id UUID --type X --category X --title X --data '{...}' [--display_hint X] [--pinned]
 *   node cli.js query --user_id UUID [--type X] [--category X] [--agent_id X] [--limit N] [--since ISO]
 *   node cli.js process-email                             # reads one email JSON from stdin
 *   node cli.js poll-shipments --user_id UUID             # polls 17track for all undelivered shipments
 */
const path = require('path');
const fs = require('fs');
const os = require('os');

// ─── Env resolution ────────────────────────────────────────────────────────

function loadEnvFile(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return false;
  for (const line of fs.readFileSync(filePath, 'utf8').split('\n')) {
    let trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    // Strip optional `export ` prefix so shell-exportable env files work too.
    if (trimmed.startsWith('export ')) trimmed = trimmed.slice('export '.length);
    const eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    const key = trimmed.slice(0, eq).trim();
    let val = trimmed.slice(eq + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    if (process.env[key] === undefined || process.env[key] === '') {
      process.env[key] = val;
    }
  }
  return true;
}

if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
  const candidates = [
    process.env.DASHBOARD_SYNC_ENV_FILE,
    path.join(os.homedir(), '.openclaw/secrets/dashboard-sync.env'),
    path.join(os.homedir(), '.openclaw/secrets/perch.env'),
    path.join(__dirname, '.env'),
  ];
  for (const p of candidates) {
    if (loadEnvFile(p)) break;
  }
}

const { dashboard_push, dashboard_query, dashboard_heartbeat } = require('./dist/index.js');
const { processEmail, pollShipments } = require('./dist/orders-autopilot.js');
const { supabase } = require('./dist/supabase.js');
const { runBackfill } = require('./dist/backfill-cli.js');

const args = process.argv.slice(2);
const cmd = args[0];

// ─── Arg parsing ───────────────────────────────────────────────────────────

function parseArgs(args) {
  const obj = {};
  for (let i = 1; i < args.length; i++) {
    if (!args[i].startsWith('--')) continue;
    const key = args[i].slice(2);
    const next = args[i + 1];
    if (next === undefined || next.startsWith('--')) {
      obj[key] = true;
      continue;
    }
    if (next === 'true') { obj[key] = true; i++; continue; }
    if (next === 'false') { obj[key] = false; i++; continue; }
    // Only number-coerce strings that look unambiguously like plain integers or decimals.
    // Avoid coercing "1e5", "0x1", "", tokens containing 'e' (emoji or keys with 'e').
    if (/^-?\d+(\.\d+)?$/.test(next)) {
      obj[key] = Number(next);
    } else {
      obj[key] = next;
    }
    i++;
  }
  return obj;
}

function readStdin() {
  return new Promise((resolve, reject) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', chunk => { data += chunk; });
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', reject);
  });
}

// ─── Commands ──────────────────────────────────────────────────────────────

async function main() {
  const params = parseArgs(args);

  if (params.data && typeof params.data === 'string') {
    try { params.data = JSON.parse(params.data); } catch {}
  }

  let result;
  switch (cmd) {
    case 'heartbeat':
      result = await dashboard_heartbeat(params);
      console.log(JSON.stringify(result, null, 2));
      break;

    case 'push':
      result = await dashboard_push(params);
      console.log(JSON.stringify(result, null, 2));
      break;

    case 'query':
      result = await dashboard_query(params);
      console.log(JSON.stringify(result, null, 2));
      break;

    case 'process-email': {
      const raw = await readStdin();
      if (!raw.trim()) {
        console.error('process-email: expected one email JSON on stdin');
        process.exit(2);
      }
      let email;
      try {
        email = JSON.parse(raw);
      } catch (e) {
        console.error('process-email: invalid JSON on stdin:', e.message);
        process.exit(2);
      }
      for (const k of ['id', 'subject', 'sender', 'date']) {
        if (!email[k]) {
          console.error(`process-email: email.${k} is required`);
          process.exit(2);
        }
      }
      if (typeof email.body !== 'string') email.body = '';
      result = await processEmail(email);
      console.log(JSON.stringify(result, null, 2));
      process.exit(result.success ? 0 : 1);
    }

    case 'poll-shipments': {
      if (!params.user_id) {
        console.error('poll-shipments: --user_id required');
        process.exit(2);
      }
      result = await pollShipments(params.user_id);
      console.log(JSON.stringify(result, null, 2));
      process.exit((result.errors && result.errors.length > 0) ? 1 : 0);
    }

    case 'record-run': {
      // Usage:
      //   cli.js record-run --agent_id X --run_type Y \
      //     [--run_id <uuid>] [--status ok|error|partial|timeout] \
      //     [--started_at ISO] [--summary '{"processed":N,...}'] [--error_detail "..."]
      //
      // If --run_id is omitted and --status=running (or unset), inserts a new
      // row and prints its id. If --run_id is supplied, updates that row with
      // ended_at + status + optional summary/error.
      if (!params.agent_id || !params.run_type) {
        console.error('record-run: --agent_id and --run_type are required');
        process.exit(2);
      }
      const summary = typeof params.summary === 'string'
        ? (() => { try { return JSON.parse(params.summary); } catch { return { raw: params.summary }; } })()
        : params.summary;

      if (params.run_id) {
        const update = {
          ended_at: new Date().toISOString(),
          status: params.status || 'ok',
        };
        if (summary !== undefined) update.summary = summary;
        if (params.error_detail) update.error_detail = String(params.error_detail).slice(0, 4000);
        const { data, error } = await supabase
          .from('agent_runs')
          .update(update)
          .eq('id', params.run_id)
          .select('id, status, ended_at')
          .maybeSingle();
        if (error) {
          console.error('record-run: update failed:', error.message);
          process.exit(1);
        }
        console.log(JSON.stringify(data, null, 2));
        process.exit(0);
      }
      // Insert new run row.
      const insert = {
        agent_id: String(params.agent_id),
        run_type: String(params.run_type),
        started_at: params.started_at || new Date().toISOString(),
        status: params.status || 'running',
      };
      if (summary !== undefined) insert.summary = summary;
      if (params.error_detail) insert.error_detail = String(params.error_detail).slice(0, 4000);
      if (params.status && params.status !== 'running') {
        insert.ended_at = new Date().toISOString();
      }
      const { data, error } = await supabase
        .from('agent_runs')
        .insert([insert])
        .select('id')
        .single();
      if (error) {
        console.error('record-run: insert failed:', error.message);
        process.exit(1);
      }
      console.log(JSON.stringify(data, null, 2));
      process.exit(0);
    }

    case 'backfill-tracker': {
      // One-time order-tracker backfill (Phase 5).
      //   --dry-run (default): fetch + plan + print counts/samples. Read-only.
      //   --apply            : perform the plan (hide/archive orders, repair
      //                        shipments). DESTRUCTIVE — guarded.
      // Always reversible at the order level (hide-not-delete); shipment repair
      // deletes phantom/duplicate rows and splits multi-piece rows.
      if (!params.user_id) {
        console.error('backfill-tracker: --user_id required');
        process.exit(2);
      }
      const apply = params.apply === true;
      if (apply) {
        // Hard guard: --apply alone is NOT enough. The operator must also pass
        // --i-understand-this-writes-prod so this can never fire by accident.
        if (params['i-understand-this-writes-prod'] !== true) {
          console.error(
            'backfill-tracker --apply is DESTRUCTIVE (sets hidden flags, deletes/splits/collapses shipment rows).\n' +
            'Refusing to run. Re-run with BOTH --apply and --i-understand-this-writes-prod once a human has\n' +
            'reviewed the --dry-run counts and explicitly approved the write.'
          );
          process.exit(3);
        }
      }
      result = await runBackfill(params.user_id, apply);

      // Human-readable summary to stderr; machine-readable JSON to stdout.
      const oc = result.orders.counts;
      const sc = result.shipments.counts;
      console.error(`\n=== backfill-tracker [${result.mode}] ===`);
      console.error(`orders: total=${result.orders.total}  keep=${oc.keep}  hide=${oc.hide}  archive=${oc.archive}`);
      console.error(
        `shipments: total=${result.shipments.total}  deleteEmpty=${sc.deleteEmpty}  ` +
        `split=${sc.split} (→${sc.splitInto} rows)  collapseDupes=${sc.collapseDupes}`
      );
      const fmtOrders = (arr) => arr.map(a => `${a.id.slice(0, 8)}:${a.reason}`).join(', ') || '(none)';
      console.error(`  sample hide:    ${fmtOrders(result.orders.sample.hide)}`);
      console.error(`  sample archive: ${fmtOrders(result.orders.sample.archive)}`);
      console.error(`  sample keep:    ${fmtOrders(result.orders.sample.keep)}`);
      console.error(`  sample deleteEmpty:  ${result.shipments.sample.deleteEmpty.map(s => s.id.slice(0, 8)).join(', ') || '(none)'}`);
      console.error(`  sample split:        ${result.shipments.sample.split.map(s => s.id.slice(0, 8) + '→[' + s.into.join(',') + ']').join('; ') || '(none)'}`);
      console.error(`  sample collapseDupes:${result.shipments.sample.collapseDupes.map(c => 'keep ' + c.keep.slice(0, 8) + ' drop ' + c.drop.length).join('; ') || '(none)'}`);
      if (result.mode === 'dry-run') {
        console.error('\nDRY-RUN: no rows were modified. Re-run with --apply --i-understand-this-writes-prod to execute.');
      } else if (result.applied) {
        const a = result.applied;
        console.error(
          `\nAPPLIED: ordersHidden=${a.ordersHidden} ordersArchived=${a.ordersArchived} ` +
          `shipmentsDeleted=${a.shipmentsDeleted} split(${a.shipmentsSplitSource}→${a.shipmentsSplitCreated}) ` +
          `collapsedDropped=${a.shipmentsCollapsedDropped}`
        );
      }
      console.log(JSON.stringify(result, null, 2));
      process.exit(0);
    }

    default:
      console.error(
        'Usage:\n' +
        '  cli.js heartbeat --agent_id X --user_id UUID [--display_name X] [--emoji X] [--model X] [--is_active true]\n' +
        "  cli.js push --agent_id X --user_id UUID --type X --category X --title X --data '{...}' [--display_hint X] [--pinned]\n" +
        '  cli.js query --user_id UUID [--type X] [--category X] [--agent_id X] [--limit N] [--since ISO]\n' +
        '  cli.js process-email                        # reads one email JSON from stdin\n' +
        '  cli.js poll-shipments --user_id UUID        # polls 17track for undelivered shipments\n' +
        "  cli.js record-run --agent_id X --run_type Y [--run_id UUID] [--status ok|error|partial|timeout] [--summary '{...}'] [--error_detail '...']\n" +
        '  cli.js backfill-tracker --user_id UUID [--dry-run | --apply --i-understand-this-writes-prod]'
      );
      process.exit(1);
  }
}

main().catch(e => { console.error(e.stack || e.message); process.exit(1); });
