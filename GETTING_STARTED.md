# The Perch — Getting Started

## What's Ready

Everything in this repo is built and ready. You need to do 3 setup steps (total ~15 minutes) before we can start flowing data.

---

## Step 1: Create a Supabase Project (~5 minutes)

1. Go to [supabase.com](https://supabase.com) and sign up (GitHub login works)
2. Click **New Project**
   - Organization: Create one (e.g., "ThePerch" or "Fabio")
   - Project name: `the-perch`
   - Database password: Generate a strong one and save it somewhere safe
   - Region: Choose the closest to Lisbon (e.g., `eu-west-1` or `eu-central-1`)
3. Wait ~2 minutes for the project to provision

### Grab your keys

Once the project is ready, go to **Settings → API** and note:

- **Project URL** — looks like `https://xyzcompany.supabase.co`
- **anon (public) key** — the short JWT (for the iOS app)
- **service_role key** — the longer JWT (for the OpenClaw skill — keep this SECRET)

---

## Step 2: Run the Database Migrations (~3 minutes)

1. In your Supabase dashboard, go to **SQL Editor**
2. Click **New Query**
3. Paste the contents of `supabase/001_initial_schema.sql` and click **Run**
4. Create another query, paste `supabase/002_seed_fabio.sql` and click **Run**

> **Note:** The seed file has a placeholder `YOUR_USER_ID`. You'll update this after you sign up through the app for the first time. For now, just run it — the agents will be created without an owner, and we'll link them later.

---

## Step 3: Configure the OpenClaw Skill (~5 minutes)

### Install the skill

```bash
# Copy the skill to your OpenClaw skills directory
cp -r skill/dashboard-sync ~/.openclaw/skills/dashboard-sync

# Install dependencies
cd ~/.openclaw/skills/dashboard-sync
npm install

# Build TypeScript
npm run build
```

### Set environment variables

Create or edit `~/.openclaw/skills/dashboard-sync/.env`:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

### Tell OpenClaw about it

Add to your `~/.openclaw/openclaw.json` (in the skills section):

```json
{
  "skills": {
    "dashboard-sync": {
      "path": "~/.openclaw/skills/dashboard-sync"
    }
  }
}
```

Then restart OpenClaw:
```bash
openclaw restart
```

### Test it

Message Claudinho on Telegram:

> "Use dashboard_heartbeat to report your status as running"

If it works, you'll see the `agents` table in Supabase update with a new `last_heartbeat` timestamp.

---

## Step 4 (Later): iOS App Setup

When we're ready to work on the app in Xcode:

1. Open `ios/ThePerch/` in Xcode
2. The Swift Package Manager dependencies will resolve automatically
3. Create `ios/ThePerch/Sources/ThePerch/Config/Secrets.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>SUPABASE_URL</key>
    <string>https://your-project.supabase.co</string>
    <key>SUPABASE_ANON_KEY</key>
    <string>eyJ...</string>
</dict>
</plist>
```

4. Add `Secrets.plist` to your `.gitignore` (it contains your API key)
5. Build and run on your iPhone or simulator

---

## What Happens Next

Once the skill is installed and working:

1. **I'll help you wire the cron jobs** — so your morning briefing, delivery tracker, and heartbeat automatically push data to Supabase
2. **You'll start seeing data** in the Supabase dashboard (Table Editor → records)
3. **We build the iOS views together** — I handle the SwiftUI code, you direct the design

---

## Project Structure

```
ThePerch/
├── GETTING_STARTED.md          ← You are here
├── architecture.md             ← Full system design doc
│
├── skill/dashboard-sync/       ← OpenClaw skill (install on Mac mini)
│   ├── SKILL.md
│   ├── src/index.ts            ← Tool handlers
│   ├── src/supabase.ts         ← Database client
│   ├── src/types.ts            ← TypeScript types
│   └── src/auto-capture.ts     ← Data parsing helpers
│
├── supabase/                   ← Database migrations
│   ├── 001_initial_schema.sql  ← Tables, RLS, indexes
│   └── 002_seed_fabio.sql      ← Initial agent + section data
│
└── ios/ThePerch/               ← iOS app (SwiftUI)
    ├── Package.swift
    └── Sources/ThePerch/
        ├── Models/             ← Data models (Record, Agent, etc.)
        ├── Services/           ← Supabase + EventKit clients
        ├── ViewModels/         ← State management
        ├── Config/             ← App configuration
        └── Utilities/          ← Date formatting, helpers
```
