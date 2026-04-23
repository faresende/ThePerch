# Agent bootstrap, paste this into your coding agent

This file is written for an AI coding agent. If you're a human, you mostly want [SHARE.md](./SHARE.md). Come back here only if you're letting an agent drive the setup, and you're okay with that.

If you **are** the agent: read the whole file before doing anything. You have enough context here to set up The Perch for your user without re-asking for basics. Do that instead of five rounds of clarifying questions.

---

## Your goal

Set up The Perch (personal iOS dashboard, Supabase-backed) for the user you're helping. By the end:

- They have a Supabase project with the schema migrated and the demo seed applied.
- They can sign in through the iOS app and see the dashboard.
- The skills they asked for are installed in their agent runtime and pointed at their Supabase.
- One test record round-trips from your writes to their iOS view.

Do not invent steps. If you need a value you don't have, ask the user for it. Bluffing is worse than pausing. Hallucinating a migration filename is a great way to break someone's database.

---

## What you need from the user, up front

Ask for all of these as a single block. Do not move on until you have them. Do not sneak them in one at a time like a bad dating profile:

1. **Runtime.** OpenClaw, Claude Code, or "just scripts." This decides which `INSTALL.md` block in each skill you follow.
2. **Supabase project URL.** `https://<your-project-ref>.supabase.co`. If they haven't made one, pause and walk them through it (SHARE.md Path B, step 1). Don't guess the URL.
3. **Supabase anon key.** The shorter JWT, from Settings → API → `anon` / `public`.
4. **Supabase service_role key.** The longer JWT. This is secret. Keep it out of git, logs, chat history, and anything the user might commit. If you paste it into a chat, you've failed.
5. **Their user UUID.** You only get this *after* they sign up through the app. Don't block on it up front, come back for it.
6. **Which skills they want.** Default set: `perch-supabase`, `dashboard-sync`, `perch-bookmarks`. Anything else needs an explicit yes. "Maybe health too?" is not a yes.

Write the credentials to a local file the user controls, not to anything synced or shared. Safe default on macOS/Linux:

```
~/.theperch/credentials.env
```

Contents:

```
SUPABASE_URL=https://<your-project-ref>.supabase.co
SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
PERCH_USER_ID=<filled-in-later>
```

`chmod 600` it. Never print the service role key back to the user after capture. They know what they gave you.

---

## The happy path, in order

### 1. Clone the repo

```bash
git clone <repo-url> ~/theperch
cd ~/theperch
```

If it's already cloned, skip. Don't re-clone "just to be safe."

### 2. Apply schema and seed

You can't run SQL against Supabase directly (no shell access). Hand the user SQL to paste instead. Do it **one block at a time** so they can confirm each step worked before moving on. Do not paste the entire migrations folder at once and wish them luck.

Blocks, in order:

1. Contents of `supabase/001_initial_schema.sql`.
2. Each file in `supabase/migrations/`, alphabetical order.
3. `supabase/002_seed_demo.sql`, but first replace `<YOUR_USER_UUID>` in the file with the user's UUID (which you'll have by now; if not, pause).

For each block, say: "Paste this into your Supabase SQL Editor and click Run. Tell me if you see an error."

Do NOT run any SQL in `supabase/personal-data/`. Those are the prior owner's one-off data fixes and they will corrupt a fresh install. If the user asks what those files are, the answer is "none of your business, don't touch them."

### 3. Help them get the iOS app running

1. Verify they have Xcode 15+. If they have Xcode 14 and say "close enough," it isn't.
2. Tell them to open `ios/ThePerch/ThePerch.xcodeproj`.
3. Remind them they can either paste their Supabase URL + anon key into the app's onboarding screen (recommended), or copy `Secrets.plist.example` → `Secrets.plist` and fill it in for dev convenience.
4. Ask them to sign up through the app on first launch.
5. Once signed up, ask them to pull their user UUID from Supabase (`SELECT id FROM auth.users ORDER BY created_at DESC LIMIT 1;`) and write it into `~/.theperch/credentials.env` as `PERCH_USER_ID`.

Then go back to step 2's seed block if you deferred it.

### 4. Install the requested skills

For each skill the user picked:

1. Read `skill/<name>/INSTALL.md`. Actually read it.
2. Pick the install block matching their runtime (OpenClaw, Claude Code, plain CLI).
3. Run the install step. For copy-paste installs that's `cp -r skill/<name> ~/.openclaw/skills/` or the equivalent.
4. Set the required env vars. Pull values from `~/.theperch/credentials.env`.
5. Read `skill/<name>/CONTRACT.md` so you know what the skill reads and writes. Never push records that don't match the contract. No freelancing, no "close enough" field names.

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

Ask the user to refresh Bookmarks in the app. If they see the record, you're done. If not, check:

- Does the `auth.uid()` in the app match the `user_id` in the insert?
- Is RLS letting the anon key read this row for this user?
- Did you use the service role key for the write? (Anon-key writes get blocked by RLS until the user is authenticated. This trips everyone up, including me, every few months.)

---

## Rules for you, the agent

- **Never commit secrets.** Not to the repo, not to logs, not to pastes. If the user says "save the service role key somewhere," use a gitignored local file. Not ~/Desktop/keys.txt.
- **Never push records to tables you don't have a contract for.** Every skill has `CONTRACT.md`. Read it first. No freelancing, no inventing fields because they'd "be useful."
- **Never touch `supabase/personal-data/`.** Those are the original owner's data fixes. They will corrupt a fresh install. I cannot be more serious about this.
- **Do not modify the iOS app source** unless the user explicitly asks. Source-level changes in The Perch are out of scope for setup. "I noticed a small improvement" is also out of scope.
- **Push back if the user pastes their service role key in chat.** Suggest they put it in `~/.theperch/credentials.env` and reference it from there. Rotate it if it already leaked.
- **When in doubt, reference [SHARE.md](./SHARE.md)** and ask the user to follow the equivalent step manually. Don't bluff. A correct "I don't know, let's check" beats a confident wrong answer every time.

---

## Common failure modes and what they mean

| Symptom | Likely cause |
|---|---|
| iOS app shows empty sections after sign-in | RLS is doing its job and there are no records yet, OR the seed wasn't run with the right user UUID |
| Insert returns `401` | Using anon key for a service-level write, or the URL is wrong, or the key is from a different project (it happens) |
| Insert returns `403` | Using anon key without an authenticated session, or RLS is rejecting the user_id check |
| Insert returns `404` on a table | Migration for that table didn't run. Check `supabase/migrations/`. |
| App crashes on launch | Supabase URL or anon key is malformed. Check `Secrets.plist` or the Keychain values. |

---

## When you're done

Report back to the user with:

1. Which skills are installed, in which runtime.
2. The env vars you set, and where (`~/.theperch/credentials.env` plus any runtime-specific config).
3. The test record you pushed, and that it's visible.
4. Anything you skipped and why.

That's the hand-off. Don't pad it with a victory lap.
