# Post-Wake Pipeline

End-to-end: drop an InBody CSV → 60s later you have a fresh BioChecha
insight on the iOS Today card AND a long-form briefing in your Telegram
DM. No chat ping required.

## The two morning slots

The 7am morning insight used to retrospect on overnight data — sleep,
HRV, weight — that wasn't actually fresh at 7am because Oura hadn't
synced yet and the user hadn't weighed in. It was reading yesterday's
numbers and pretending they were last night's. The fix is to split
"morning" into two distinct moments:

| Slot | Trigger | Character | Surfaces |
|---|---|---|---|
| `morning` | 7am cron (Lisbon) | **Forward-looking only.** Today's training, today's macros, calendar load. No retrospection on sleep/weight (would be stale). | iOS card |
| `morning_post_wake` | InBody watcher OR manual | **Retrospective + forward-aware.** Last night's sleep, body-comp delta vs trailing average. Plan adjusted on fresh data. | iOS card + Telegram DM |

The slot the user actually feels as "morning summary" is
`morning_post_wake`. The 7am pre-wake card is now a quiet plan-of-the-day.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  User: weighs in on InBody H30 → exports CSV from LookinBody     │
│        Connect → file lands in ~/Documents/InBody/              │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  launchd: com.theperch.inbody-watcher                            │
│    Polls ~/Documents/InBody/ every 60s                          │
│    On finding InBody-*.csv → runs scripts/inbody-watch-tick.sh   │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  inbody_ingest.py                                                │
│    Parses CSV → 22 metrics                                       │
│    Bulk-upserts to public.health_metrics (source='inbody')       │
│    Deletes the CSV                                               │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│  biochecha_post_wake_insight.py                                  │
│    gather_state('morning_post_wake') — pulls fresh sleep + body  │
│    rank() over post-wake categories                              │
│                                                                  │
│    [iOS path]  → _generate_insight (short)  → _upsert_insight    │
│    [TG  path]  → _generate_telegram_summary → _telegram_client   │
│                                                                  │
│    iOS-first ordering: TG failure never blocks the card update.  │
└──────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┴────────────────┐
              ▼                                ▼
┌──────────────────────────┐      ┌──────────────────────────────┐
│ public.insights          │      │ Telegram (BioChecha bot DM)  │
│ insight_type =           │      │ 200-400 char Markdown brief, │
│ 'daily_health_morning_   │      │ multi-section, with numbers. │
│  post_wake'              │      │                              │
│                          │      │ Same 20% snark voice rules.  │
│ iOS DailyInsightCard     │      │                              │
│ pulls latest BioChecha   │      │                              │
│ row for today on refresh.│      │                              │
└──────────────────────────┘      └──────────────────────────────┘
```

## Why polling, not WatchPaths

launchd's FSEvents subscription on `~/Documents/` is blocked by macOS
TCC (Transparency, Consent, Control) sandboxing without Full Disk
Access. Polling sidesteps the permission dance: the tick script runs
under the user's launchd context with the same access as a normal
shell script. For a once-a-day weigh-in, 60s latency is invisible.

If you want sub-second response, grant `bash` Full Disk Access in
System Settings → Privacy & Security → Full Disk Access, then change
the plist's `StartInterval` to a `WatchPaths` array. The tick script
itself is unchanged.

## Source-of-truth precedence

When two ingest sources write the same metric for the same day,
the higher-priority source wins.

```
Body composition: InBody  > Withings
Sleep:            Oura    > 8sleep
```

Implementation: `biochecha_dynamic_insight.py:_pick_by_priority`. The
gather functions (`_gather_body_comp_last_30`, `_gather_sleep_last_7`)
fetch all rows including the `source` column, then collapse to one
row per (day, metric) using the priority ranking.

Add a new source: append it to `BODY_COMP_SOURCE_PRIORITY` or
`SLEEP_SOURCE_PRIORITY` at the position you want. Sources outside the
priority list rank last (still surfaced when no other source has data).

## Setup checklist (new Mac)

1. **Symlink scripts to runtime location:**
   ```bash
   mkdir -p ~/.openclaw/workspace/scripts
   ln -s ~/Developer/ThePerch/agents/health-integrations \
         ~/.openclaw/workspace/scripts/health-integrations
   ```

2. **Secrets in `~/.openclaw/secrets/perch.env`** (see
   `agents/health-integrations/README.md` for the full list).

3. **Telegram bot config** in `~/.openclaw/secrets.json` and
   `~/.openclaw/openclaw.json` under
   `/channels/telegram/accounts/biochecha/`. The bot token is read
   automatically; the chat_id is resolved from the `allowFrom` list.

4. **launchd watcher** — install via the renderer script. The committed
   plist is a `.template` with placeholder paths; the script substitutes
   the chosen `WATCH_DIR` / `LOG_DIR` and `launchctl load`s the result.
   Re-run any time to update.
   ```bash
   ./scripts/install-inbody-watcher.sh                          # default ~/Documents/InBody
   WATCH_DIR=~/iCloud/InBody ./scripts/install-inbody-watcher.sh  # override
   ```

5. **Watch directory exists:**
   ```bash
   mkdir -p ~/Documents/InBody
   ```
   Configure LookinBody Connect's CSV export destination to land here.

6. **Backfill historical scans (one-time, if you have the legacy
   `body-composition.json`):**
   ```bash
   set -a && source ~/.openclaw/secrets/perch.env && set +a
   python3 agents/health-integrations/inbody_backfill_from_json.py
   ```
   Idempotent — re-running is a no-op (existing rows upsert by
   timestamp-based source_id).

## Daily flow once installed

1. Wake up.
2. Open Oura on phone (lets it sync overnight data).
3. Step on InBody H30. Reading goes to LookinBody Connect on phone.
4. Export the day's CSV from LookinBody Connect → `~/Documents/InBody/`.
5. Walk away.
6. Within ≤60s:
   - The CSV is ingested + deleted
   - iOS card refreshes with the post-wake summary
   - BioChecha texts you the long-form briefing on Telegram
7. Pull-to-refresh on the iOS app to see the new card.

The flow is **idempotent** — if you drop the same CSV twice, the
second run upserts (no duplicates). If the watcher fails for any
reason, drop the CSV again or run the tick manually:

```bash
~/Developer/ThePerch/scripts/inbody-watch-tick.sh
```

## Troubleshooting

### iOS card didn't update / Telegram DM didn't arrive

```bash
# 1. Is the watcher loaded?
launchctl list | grep inbody-watcher

# 2. Did it fire? Check logs.
tail -50 ~/.openclaw/logs/inbody-watcher.out.log
tail -50 ~/.openclaw/logs/inbody-watcher.err.log

# 3. Was the CSV consumed?
ls ~/Documents/InBody/InBody-*.csv

# 4. Did agent_runs record the run?
# Open Supabase Studio → public.agent_runs, filter agent_id='biochecha'
# run_type='inbody_ingest' or 'post_wake_insight'.
```

### "Body fat dropped 6%" or other unrealistic deltas

Either:
- The trailing average is sparse. The post-wake category needs ≥2
  prior weigh-ins; until then, output is muted (`note: "early_data"`).
- A lower-priority source has a mis-calibrated reading sneaking in.
  Confirm with `SELECT source, value FROM health_metrics WHERE
  metric='body_fat_pct' AND measured_at::date > now() - 7;` and remove
  the bad source if needed.

### CSV not consumed (still sitting in `~/Documents/InBody/`)

Run the tick manually with verbose tracing:

```bash
bash -x ~/Developer/ThePerch/scripts/inbody-watch-tick.sh
```

Common causes:
- `~/.openclaw/secrets/perch.env` missing or broken
- Network failure to Supabase (`agent_runs` row will have the error)
- Parse error on the CSV (the file stays so you can investigate)

## Why this design

- **No chat dependency.** The previous flow needed BioChecha-the-agent
  to be active in Telegram. The watcher needs nothing.
- **Two surfaces, one trigger.** iOS card and Telegram both fire from
  the same fact bundle, so they can't go out of sync.
- **iOS-first ordering.** Telegram failure never blocks the card.
- **Idempotent.** The same CSV can land in the watch folder any number
  of times without producing duplicates.
- **Sources of truth are explicit.** When InBody and Withings both
  weigh in on the same day, you know which one shows up in the
  insight without reading code.
