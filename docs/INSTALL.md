# Installation (the slow way)

> **Want this faster?** Hand `SETUP-FOR-AGENTS.md` (in the repo root) to an openclaw agent and let it do the whole thing. This page is for if you'd rather do it yourself.

## What you need

- macOS, Apple Silicon, Xcode 15+
- Node 22+ (`brew install node`)
- Python 3.11+ (`brew install python`)
- A [Supabase](https://supabase.com) account (free tier is fine)
- [openclaw](https://github.com/anthropics/openclaw) installed and used at least once
- Optional integrations (skip what you don't need): Withings developer app, 8sleep account, [17track](https://api.17track.net) API key, [Karakeep](https://github.com/karakeep-app/karakeep) instance, OpenAI API key

## 14 steps

### 1. Supabase project

Create a project at https://supabase.com/dashboard. Once it's ready, grab from **Settings → API**:

- Project URL
- `anon` (public) key
- `service_role` (private) key

Don't paste the service_role anywhere committable.

### 2. Run migrations

```bash
cd ~/Developer/ThePerch/supabase/migrations
ls *.sql | sort
```

Paste each `.sql` file into Supabase's SQL Editor in filename order. Or:

```bash
supabase db push --project-ref <YOUR-PROJECT-REF>
```

### 3. Create your user

In Supabase: **Authentication → Users → Add user**. Pick an email + password. Copy the resulting UUID.

Then in the SQL Editor:

```sql
INSERT INTO public.users (id, display_name)
VALUES ('<your-user-uuid>', 'Your Name');
```

### 4. Install the openclaw skill

```bash
cd ~/Developer/ThePerch/skill/dashboard-sync
npm install
npm run build
ln -sf ~/Developer/ThePerch/skill/dashboard-sync ~/.openclaw/skills/dashboard-sync
```

### 5. Write `~/.openclaw/secrets/perch.env`

```bash
mkdir -p ~/.openclaw/secrets && chmod 700 ~/.openclaw/secrets

cat > ~/.openclaw/secrets/perch.env <<'EOF'
export SUPABASE_URL=https://<YOUR-PROJECT-REF>.supabase.co
export SUPABASE_SERVICE_ROLE_KEY=<your-service-role-key>
export PERCH_USER_ID=<your-user-uuid>

# Optional integrations — fill in what you want, leave blank what you don't:
export OPENAI_API_KEY=
export WITHINGS_CLIENT_ID=
export WITHINGS_CLIENT_SECRET=
export EIGHT_SLEEP_EMAIL=
export EIGHT_SLEEP_PASSWORD=
export SEVENTEEN_TRACK_API_KEY=
EOF

chmod 600 ~/.openclaw/secrets/perch.env
```

### 6. Symlink agent scripts

```bash
mkdir -p ~/.openclaw/workspace/scripts/health-integrations
ln -sf ~/Developer/ThePerch/agents/health-integrations/* \
       ~/.openclaw/workspace/scripts/health-integrations/
```

### 7. BioChecha (optional)

Needs an OpenAI API key. ~$0.0001 per insight (gpt-4o-mini). Add `OPENAI_API_KEY` to perch.env, then:

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/.openclaw/workspace/scripts/health-integrations/biochecha_daily_insight.py
```

First run says "Quiet data day" — expected, no health data yet.

### 8. Withings (optional)

1. Go to https://developer.withings.com/dashboard/. Create a personal app.
2. Set redirect URI to: `http://localhost:8127/withings/callback`
3. Paste `client_id` + `client_secret` into `perch.env`.
4. One-time OAuth handshake:

   ```bash
   set -a && source ~/.openclaw/secrets/perch.env && set +a
   python3 ~/.openclaw/workspace/scripts/health-integrations/withings_setup.py
   ```

5. Backfill:

   ```bash
   python3 ~/.openclaw/workspace/scripts/health-integrations/withings_ingest.py
   ```

### 9. 8sleep (optional, may break)

Reverse-engineered. May break when 8sleep ships a new app. Caveat emptor.

Add `EIGHT_SLEEP_EMAIL` + `EIGHT_SLEEP_PASSWORD` to perch.env, then:

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/.openclaw/workspace/scripts/health-integrations/eight_sleep_ingest.py
```

### 10. 17track (optional)

Sign up at https://api.17track.net/, get an API key. Add `SEVENTEEN_TRACK_API_KEY` to perch.env.

### 11. Cron jobs

Add three entries to `~/.openclaw/cron/jobs.json` — see `SETUP-FOR-AGENTS.md` for the exact JSON shapes. They run:

- 8sleep ingest, every 30 min
- Withings ingest, hourly
- BioChecha daily insight, 7am local time

Adjust the `tz` field for your timezone.

### 12. LaunchAgent for shipment polling

```bash
~/Developer/ThePerch/ops/install-launchagent.sh
```

Polls 17track every 30 min for delivery status + ETA updates. Logs at `~/.openclaw/logs/poll-shipments.log`.

### 13. iOS app

```bash
open ~/Developer/ThePerch/ios/ThePerch/ThePerch.xcodeproj
```

In Xcode:
1. **Project → Signing & Capabilities → Team** — set to your personal team.
2. **Bundle identifier** — change to something unique (`<yourdomain>.ThePerch`).
3. Copy `Sources/ThePerch/Config/Secrets.example.xcconfig` → `Secrets.xcconfig` (gitignored). Fill in:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY` (the anon one, NOT service_role)
   - `KARAKEEP_BASE_URL` and `KARAKEEP_TOKEN` — leave blank if no Karakeep
4. Build + Run on **device** (not simulator).

### 14. Smoke test

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/.openclaw/workspace/scripts/health-integrations/withings_ingest.py
python3 ~/.openclaw/workspace/scripts/health-integrations/eight_sleep_ingest.py
python3 ~/.openclaw/workspace/scripts/health-integrations/biochecha_daily_insight.py
```

Open the app. Today tab should show today's BioChecha card + (eventually) the sleep graph as data accumulates.

## Common stumbles

| Symptom | Fix |
|---|---|
| "Missing env" from Python script | You didn't `source perch.env` in the shell that's running it. |
| Withings ingest writes 0 | Last weigh-in is older than the lookback window (default 60 days). Adjust in `withings_ingest.py`. |
| 8sleep "session token not supported" | 8sleep updated their auth flow. Open an issue. |
| BioChecha card stuck on "BioChecha takes the morning…" | Insight didn't generate or didn't decode. Check `agent_runs` table in Supabase for errors. |
| Bookmarks tab says "not configured" | You didn't set `KARAKEEP_BASE_URL` + `KARAKEEP_TOKEN`. This is the intended state — leave it or hook up a Karakeep instance. |
| Build fails with "no such module 'PerchSharedKit'" | Hit `File → Packages → Reset Package Caches` in Xcode. |

## Done

It's running. Forget about it for a week, then come back and see what your data looks like rendered in serif italic.
