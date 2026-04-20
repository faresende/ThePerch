# Share The Perch with a friend

This is the canonical install guide. Follow it end-to-end and you'll have The Perch running in about 30 minutes. If you'd rather hand most of this to a coding agent, see [AGENT_BOOTSTRAP.md](./AGENT_BOOTSTRAP.md) instead — come back here for the manual bits.

There are three paths depending on what you want out of The Perch. Pick one.

---

## Path A — Just the iOS app, demo data

**Time: ~10 minutes** • **You need:** a Mac with Xcode 15+ and an iPhone or iOS simulator.

This path gets the app running against mock data — no Supabase, no agents. Good for previewing the UI and deciding if you want to go deeper.

1. Clone this repo.
2. Open `ios/ThePerch/ThePerch.xcodeproj` in Xcode.
3. Select the `ThePerch` scheme + an iOS simulator.
4. Run (⌘R).
5. The app will launch into onboarding. Skip it and you'll see mock data.

You're done. Everything past this point is about wiring real data.

---

## Path B — Full self-host

**Time: ~30 minutes** • **You need:** Mac + Xcode, a Supabase account (free tier is fine), and a terminal.

### 1. Create a Supabase project (5 min)

1. Sign up at [supabase.com](https://supabase.com) if you haven't already.
2. **New Project** → give it a name (e.g. `the-perch`), a strong DB password, and pick a region close to you.
3. Wait ~2 minutes for provisioning.
4. Go to **Settings → API** and copy:
   - **Project URL** — `https://<your-project-ref>.supabase.co`
   - **anon (public) key** — the shorter JWT, safe for client apps
   - **service_role key** — the longer JWT, **keep this secret**

### 2. Run the migrations + seed (5 min)

In the Supabase dashboard, open **SQL Editor → New Query**, then run these files **in order**:

1. `supabase/001_initial_schema.sql`
2. `supabase/migrations/001_enable_rls.sql`
3. `supabase/migrations/002_users_table.sql`
4. `supabase/migrations/003_card_system.sql`
5. `supabase/migrations/004_food_memory.sql`
6. `supabase/migrations/005_orders_shipments.sql`
7. Any dated migrations in `supabase/migrations/` you want to apply in alphabetical order.

Then **sign up a user** through the app's onboarding or directly in the dashboard (Authentication → Users → Add user).

Find your user's UUID:

```sql
SELECT id FROM auth.users ORDER BY created_at DESC LIMIT 1;
```

Open `supabase/002_seed_demo.sql`, replace `<YOUR_USER_UUID>` with that UUID, and run it in the SQL Editor. You now have a minimum-viable set of agents + sections.

### 3. Run the iOS app against your Supabase (5 min)

1. Open `ios/ThePerch/ThePerch.xcodeproj` in Xcode.
2. Either:
   - **Onboarding path** (recommended): run the app, and on the onboarding screen paste your **Project URL** + **anon key**. The app stores them in your device Keychain.
   - **Dev path**: copy `ios/ThePerch/Sources/ThePerch/Config/Secrets.plist.example` → `Secrets.plist` and fill in the values.
3. Sign up / log in inside the app.
4. You should now see the dashboard with the sections from the demo seed.

### 4. Pick your skills and install them (10 min)

Only install what you actually want to use. Every skill has an `INSTALL.md` with three install blocks — OpenClaw, Claude Code, or plain CLI. Skim the table in [README.md](./README.md) and pick a starting set.

A reasonable first set is:

```
skill/perch-supabase    (always — foundational reference)
skill/dashboard-sync    (the core write tool)
skill/perch-bookmarks   (zero dependencies, good for testing the loop)
```

Follow each skill's `INSTALL.md`. Most come down to "copy the folder to `~/.openclaw/skills/` or `~/.claude/skills/`, and set these env vars."

### 5. Push your first record

Send one record through `dashboard-sync` or directly:

```bash
curl -X POST "https://<your-project-ref>.supabase.co/rest/v1/dashboard_records" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{
    "user_id": "<YOUR_USER_UUID>",
    "agent_id": "assistant",
    "type": "text_note",
    "category": "admin",
    "title": "Hello from the CLI",
    "data": {"message": "If you see this in the app, it works."},
    "display_hint": "single_value"
  }'
```

Refresh the app. Your record should appear.

---

## Path C — Guided by an agent

**Time: ~15 minutes** • **You need:** a coding agent you trust (OpenClaw, Claude Code, or similar), a Supabase account, and a Mac for the iOS build.

1. Create a Supabase project (see Path B, step 1).
2. Note your **Project URL**, **anon key**, **service_role key**, and — once you sign up through the app — your **user UUID**.
3. Open a chat with your agent, paste the contents of [AGENT_BOOTSTRAP.md](./AGENT_BOOTSTRAP.md), and answer its questions.
4. Follow the agent's instructions through the build + sign-in + data-push steps.

The agent knows how to:
- run migrations in the Supabase SQL editor on your behalf (by handing you SQL to paste),
- install skills into OpenClaw or Claude Code,
- push a test record once everything's wired,
- diagnose common failures (RLS blocking reads, missing env vars, etc.).

---

## After setup

- **Add more skills** over time. Each one is independent.
- **Write your own skill.** Copy an existing skill's folder layout (`SKILL.md`, `INSTALL.md`, `CONTRACT.md`, `scripts/`, `providers/`). The contract is: your skill writes to `dashboard_records` (or one of the canonical tables) with the right `category` + `type` + `display_hint`, and the iOS app picks it up.
- **Hit a wall?** Open an issue describing what you did and what went wrong. Include the agent runtime you're using, your OS, and any error messages.

---

## iOS distribution: today vs. later

Right now the only supported install path for the iOS app is **build from source in Xcode**. A TestFlight link will come later — see [ios/TESTFLIGHT.md](./ios/TESTFLIGHT.md) for the status.
