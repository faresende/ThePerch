# Share The Perch with a friend

This is the canonical install guide. End-to-end, it's about 30 minutes, assuming nothing goes sideways. If you'd rather hand most of it to a coding agent, jump to [AGENT_BOOTSTRAP.md](./AGENT_BOOTSTRAP.md) and come back here for the manual bits.

There are three paths, depending on how deep you want to go. Pick one. Don't try to do all three at once, you will get confused.

---

## Path A, just the iOS app with demo data

**Time: ~10 minutes.** **You need:** a Mac with Xcode 15+ and an iPhone or simulator.

This gets the app running against mock data. No Supabase, no agents, no commitment. Good for kicking the tires before deciding if you want the full thing.

1. Clone this repo.
2. Open `ios/ThePerch/ThePerch.xcodeproj` in Xcode.
3. Select the `ThePerch` scheme and an iOS simulator.
4. Run (⌘R).
5. The app launches into onboarding. Skip it and you'll see mock data.

Done. Everything past this point is about wiring real data.

---

## Path B, full self-host

**Time: ~30 minutes.** **You need:** Mac + Xcode, a Supabase account (free tier is fine), and a terminal. Coffee helps.

### 1. Create a Supabase project (5 min)

1. Sign up at [supabase.com](https://supabase.com) if you haven't already.
2. **New Project** → give it a name (`the-perch` works), a strong DB password (save it, I won't have it for you), pick a region close to you.
3. Wait about two minutes for provisioning. Go stretch.
4. Go to **Settings → API** and copy:
   - **Project URL**, `https://<your-project-ref>.supabase.co`
   - **anon (public) key**, the shorter JWT, safe for client apps
   - **service_role key**, the longer JWT, **keep this one secret**. Leaking it is how hobby projects end up on Hacker News.

### 2. Run the migrations and seed (5 min)

In the Supabase dashboard, open **SQL Editor → New Query**, then run these files **in order**:

1. `supabase/001_initial_schema.sql`
2. `supabase/migrations/001_enable_rls.sql`
3. `supabase/migrations/002_users_table.sql`
4. `supabase/migrations/003_card_system.sql`
5. `supabase/migrations/004_food_memory.sql`
6. `supabase/migrations/005_orders_shipments.sql`
7. Any dated migrations in `supabase/migrations/`, alphabetical order. Don't get creative.

Then **sign up a user**, either through the app's onboarding or directly in the dashboard (Authentication → Users → Add user).

Grab your user's UUID:

```sql
SELECT id FROM auth.users ORDER BY created_at DESC LIMIT 1;
```

Open `supabase/002_seed_demo.sql`, replace `<YOUR_USER_UUID>` with that UUID, and run it. You now have a minimum-viable set of agents and sections. Congratulations, you own a dashboard.

### 3. Run the iOS app against your Supabase (5 min)

1. Open `ios/ThePerch/ThePerch.xcodeproj`.
2. Pick one:
   - **Onboarding path (recommended):** run the app, and on the onboarding screen paste your **Project URL** + **anon key**. The app stores them in your device Keychain. Like a grown-up.
   - **Dev path:** copy `ios/ThePerch/Sources/ThePerch/Config/Secrets.plist.example` → `Secrets.plist` and fill it in. Don't commit that file.
3. Sign up or log in inside the app.
4. You should see the dashboard with the demo-seed sections. If you don't, skip to the failure-mode table in AGENT_BOOTSTRAP.md.

### 4. Pick your skills and install them (10 min)

Only install the ones you'll actually use. The "I'll set it up in case I need it" instinct is a trap. Every skill ships with an `INSTALL.md` that has three install blocks: OpenClaw, Claude Code, plain CLI. Skim the table in [README.md](./README.md) and pick a starting set.

A reasonable first set:

```
skill/perch-supabase    (always, foundational reference)
skill/dashboard-sync    (the core write tool)
skill/perch-bookmarks   (zero dependencies, good for testing the loop end-to-end)
```

Follow each skill's `INSTALL.md`. Most of them come down to "copy the folder into `~/.openclaw/skills/` or `~/.claude/skills/`, set these env vars."

### 5. Push your first record

Fire one record through `dashboard-sync`, or straight at the REST API:

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

Pull to refresh in the app. Your record should show up. If it doesn't, AGENT_BOOTSTRAP.md has a failure-mode table at the bottom. 90% of the time it's RLS.

---

## Path C, guided by an agent

**Time: ~15 minutes.** **You need:** a coding agent you trust (OpenClaw, Claude Code, or similar), a Supabase account, and a Mac for the iOS build.

1. Create a Supabase project (Path B, step 1).
2. Note your **Project URL**, **anon key**, **service_role key**, and, once you sign up through the app, your **user UUID**.
3. Open a chat with your agent, paste the contents of [AGENT_BOOTSTRAP.md](./AGENT_BOOTSTRAP.md), and answer its questions.
4. Follow the agent through the build, sign-in, and data-push steps. Resist the urge to micromanage.

A competent agent with that bootstrap can:
- hand you SQL to paste into the Supabase SQL editor,
- install skills into OpenClaw or Claude Code,
- push a test record once everything's wired,
- diagnose the common failures (RLS blocking reads, missing env vars, bad URLs, you know, the usual).

---

## After setup

- **Add more skills** over time. They're independent by design. No fear of big-bang migrations.
- **Write your own skill.** Copy the layout of an existing one (`SKILL.md`, `INSTALL.md`, `CONTRACT.md`, `scripts/`, `providers/`). The contract is the same for all of them: write to `dashboard_records` (or one of the canonical tables) with the right `category`, `type`, and `display_hint`, and the iOS app picks it up. That's it. Really.
- **Stuck?** Open an issue describing what you did and what broke. Include the agent runtime you're using, your OS, and any error messages. Vague bug reports produce vague fixes. "It doesn't work on my Mac" is not a bug report.

---

## iOS distribution: today vs. later

Right now the only supported install path for the iOS app is **build from source in Xcode**. A TestFlight link will come later, whenever "later" means. See [ios/TESTFLIGHT.md](./ios/TESTFLIGHT.md) for the current status.
