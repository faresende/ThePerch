# Agent bootstrap — paste this into your coding agent

This file is written for an AI coding agent. If you're a human, you mostly want [SHARE.md](./SHARE.md) instead — come back here only if you're letting an agent drive the setup.

If you **are** the agent: read the whole file before doing anything. You have enough context here to set up The Perch for your user without re-asking for basics.

---

## Your goal

Set up The Perch (personal iOS dashboard, Supabase-backed) for the user you are helping. By the end:

- They have a Supabase project with the schema migrated and a demo seed applied.
- They can sign in through the iOS app and see the dashboard.
- The skills they asked for are installed in their agent runtime and pointing at their Supabase.
- One test record round-trips from your writes to their iOS view.

Do not invent steps. If you need a value you don't have, ask the user for it.

---

## What you need from the user, up front

Ask for these as a single block. Do not move on until you have all of them:

1. **Runtime** — OpenClaw, Claude Code, or "just scripts." This changes which `INSTALL.md` block in each skill you follow.
2. **Supabase project URL** — `https://<your-project-ref>.supabase.co`. If the user hasn't made one yet, pause and walk them through creating one (SHARE.md Path B, step 1).
3. **Supabase anon key** — the shorter JWT from Settings → API → `anon` / `public`.
4. **Supabase service_role key** — the longer JWT. This is secret. Keep it out of git, chat logs, and any file the user might commit.
5. **Their user UUID** — you'll get this *after* they sign up through the app. Don't block on it up front; come back for it.
6. **Which skills they want**. Default set: `perch-supabase`, `dashboard-sync`, `perch-bookmarks`. Anything else should be an explicit yes.

Write the credentials to a local file the user controls, not to something synced/shared. A safe default on macOS/Linux:

```
~/.theperch/credentials.env
```

with contents:

```
SUPABASE_URL=https://<your-project-ref>.supabase.co
SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
PERCH_USER_ID=<filled-in-later>
```

`chmod 600` it. Never print the service role key back to the user after capture.

---

## The happy path (do this in order)

### 1. Clone the repo

```bash
git clone <repo-url> ~/theperch
cd ~/theperch
```

If the repo is already cloned, skip.

### 2. Apply schema + seed

You cannot run SQL against Supabase directly (no shell access). Instead, hand the user SQL to paste. Do it **one block at a time** so the user can confirm each step worked.

Blocks, in order:

1. The contents of `supabase/001_initial_schema.sql`.
2. Each file in `supabase/migrations/` in alphabetical order.
3. `supabase/002_seed_demo.sql` — but first replace `<YOUR_USER_UUID>` in the file with the user's UUID (which you'll have by this point; if not, pause).

For each block: tell the user "Paste this into your Supabase SQL Editor and click Run. Tell me if you see an error."

Do NOT run any SQL in `supabase/personal-data/`. Those are the prior owner's one-off data fixes.

### 3. Help them get the iOS app running

1. Verify they have Xcode 15+.
2. Tell them to open `ios/ThePerch/ThePerch.xcodeproj`.
3. Remind them they can either paste their Supabase URL + anon key into the app's onboarding screen (recommended) or copy `Secrets.plist.example` → `Secrets.plist` and fill it in for dev convenience.
4. Ask them to sign up through the app on first launch.
5. Once signed up, ask them to pull their user UUID from Supabase (SQL: `SELECT id FROM auth.users ORDER BY created_at DESC LIMIT 1;`) and write it into `~/.theperch/credentials.env` as `PERCH_USER_ID`.

Now go back to step 2's seed block if you deferred it.

### 4. Install the requested skills

For each skill the user picked:

1. Read `skill/<name>/INSTALL.md`.
2. Pick the install block matching their runtime (OpenClaw / Claude Code / plain CLI).
3. Run the install step. For copy-paste installs this is `cp -r skill/<name> ~/.openclaw/skills/` or similar.
4. Set the required env vars. Pull values from `~/.theperch/credentials.env`.
5. Read `skill/<name>/CONTRACT.md` so you understand what this skill reads/writes. Never push records that don't match the contract.

### 5. Smoke test

Send one record end-to-end. Simplest target: a bookmark.

```bash
source ~/.theperch/credentials.env
curl -X POST "$SUPABASE_URL/rest/v1/records" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "{
    \"user_id\": \"$PERCH_USER_ID\",
    \"agent_id\": \"assistant\",
    \"category\": \"bookmarks\",
    \"type\": \"bookmark\",
    \"title\": \"SwiftUI Documentation\",
    \"data\": {
      \"url\": \"https://developer.apple.com/documentation/swiftui\",
      \"tags\": [\"test\"]
    }
  }"
```

Ask the user to refresh the Bookmarks section in the app. If they see the record, you're done. If not, check:

- Did the `auth.uid()` in the app match the `user_id` in the insert?
- Is RLS letting the anon key read this row for this user?
- Did you use the service role key for the write? (Anon key writes will be blocked by RLS until the user is authenticated.)

---

## Rules for you, the agent

- **Never commit secrets.** Not to the repo, not to logs, not to pastes. If the user says "save the service role key somewhere," use a gitignored local file.
- **Never push records to tables you don't have a contract for.** Every skill has `CONTRACT.md`. Read it first.
- **Never touch `supabase/personal-data/`.** Those are the original owner's data fixes. They will corrupt a fresh install if run.
- **Do not modify the iOS app source.** Unless the user explicitly asks you to. Source-level changes in The Perch are out of scope for setup.
- **Push back if the user pastes their service role key in chat.** Suggest they put it in `~/.theperch/credentials.env` instead and reference it from there.
- **When in doubt, reference [SHARE.md](./SHARE.md)** and ask the user to follow the equivalent step manually. Don't bluff.

---

## Common failure modes and what they mean

| Symptom | Likely cause |
|---|---|
| iOS app shows empty sections after sign-in | RLS is correctly filtering and there are no records yet, OR the seed wasn't run with the right user UUID |
| Insert returns `401` | Using anon key for service-level writes, or the URL is wrong |
| Insert returns `403` | Using anon key without authenticated session, or RLS is rejecting the user_id check |
| Insert returns `404` on a table | Migration for that table wasn't run; check `supabase/migrations/` |
| App crashes on launch | Supabase URL or anon key is malformed — check `Secrets.plist` or the Keychain values |

---

## When you're done

Report back to the user with:

1. Which skills are installed and in which runtime.
2. The env vars you set, and where (`~/.theperch/credentials.env` + any runtime-specific config).
3. The test record you pushed and confirmed visible.
4. Anything you skipped and why.

That's the hand-off.
