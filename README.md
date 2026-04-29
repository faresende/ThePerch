# The Perch

A personal life dashboard for iOS. The kind that knows what your sleep was like last night, that the package you ordered is arriving Tuesday, and that you should probably eat something with protein in it today. It's powered by a fleet of small agents that write structured data into Supabase, and an iOS app that reads it out and renders it in a tone that doesn't sound like a fitness watch.

Built for one user. Yours, hopefully, not mine.

> **Status:** mostly works. Some parts are reverse-engineered (8sleep doesn't have an official API). Some parts are opinionated to the point of being weird (the BioChecha insight engine writes you a 50-word morning briefing in serif italic, because of course it does). PRs welcome but the bar is "do you also want this exact thing."

---

## What it is

```
                ┌────────────────────┐
                │  The Perch (iOS)   │   ← reads, displays, never writes
                └─────────┬──────────┘
                          │ Supabase (RLS, owner-scoped)
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
   ┌────────┐      ┌──────────┐      ┌────────────┐
   │ Agents │      │ Skills   │      │ Cron jobs  │
   │ (.py)  │      │ (.ts)    │      │ (.plist)   │
   └────────┘      └──────────┘      └────────────┘
   8sleep,         Email scanner,   17track polling,
   Withings,       order detection, daily insight,
   BioChecha       parse trace      health ingest
```

The iOS app does no scraping, no parsing, no integrations. It only reads. Everything that puts data in front of you is written by an agent or a skill running on your machine — either via openclaw (recommended) or by hand.

What you see in the app:

- **Today** — BioChecha's daily insight (LLM-generated from your real data), nutrition, calendar today, active orders, calendar tomorrow, sleep graph
- **Health** — sleep trends, body composition, HRV, RHR, room temperature
- **Hub** — orders (with carrier ETAs), bookmarks, calendar, travel
- **Settings** — backend swap, profile, beta toggles

---

## Who is this for

You, if:
- you run **openclaw** (or are willing to)
- you are okay with **iOS-only** (no Android, no web)
- you have a **Supabase** account (free tier is fine)
- you're already paying for **8sleep** and/or **Withings** and want their data somewhere you actually look at it
- "self-hosted personal dashboard" is your idea of a good Saturday
- you're allergic to subscription apps that show you a ring

Not you, if:
- you want a polished, supported product. This is a personal project shaped like a public repo.
- you wanted Android or web. Won't happen here.
- you don't want to think about cron jobs. There are cron jobs.

---

## Installation

The fast way: hand `SETUP-FOR-AGENTS.md` to an openclaw agent and let it do the whole thing. It's been written specifically so a Claude can read it once and execute the setup end-to-end.

The slow way: read [`docs/INSTALL.md`](docs/INSTALL.md) and do it yourself.

Either way, you'll need:

1. A Supabase project (free tier)
2. Xcode 15+ on a Mac with Apple Silicon
3. Node 22+
4. Python 3.11+
5. **(Optional)** 8sleep account, Withings developer app, 17track API key, Karakeep instance, OpenAI API key for BioChecha. Each integration is independent — skip the ones you don't have. The app degrades to "no data" empty states for missing sources.

---

## Architecture in 5 bullets

- **iOS app** in `ios/ThePerch/` — SwiftUI, iOS 17+. Single source of truth: `DashboardViewModel`. Reads from Supabase via `anon` key + RLS. Never writes anything users haven't manually requested.
- **Skill** in `skill/dashboard-sync/` — TypeScript, Node 22+. Runs on cron under openclaw. Scans your inbox for order/shipping emails, classifies via tier1 keyword regex → tier2 LLM → tier3 learned-senders. Writes orders + shipments + parse_trace.
- **Agents** in `agents/health-integrations/` — Python. 8sleep, Withings, BioChecha. All read from Supabase (read-only) and write back to Supabase (service-role).
- **Migrations** in `supabase/migrations/` — SQL, idempotent, replayable on a fresh project. Order matters; run them in filename order.
- **Specs** in `docs/superpowers/specs/` — design docs for every meaningful feature, written in advance via the `superpowers:brainstorming` skill. Decisions ledger.

---

## Configuration

Three layers:

| Where | What lives there |
|---|---|
| `~/.openclaw/secrets/perch.env` | Server-side: Supabase service-role key, OpenAI key, Withings/8sleep/17track tokens |
| `ios/ThePerch/Sources/ThePerch/Config/Secrets.xcconfig` | iOS-side: Supabase anon key, optional Karakeep token. **Gitignored.** |
| `~/.openclaw/state/*-tokens.json` | OAuth refresh tokens (Withings). Auto-managed; don't edit by hand. |

The `.env.example` and `Secrets.example.xcconfig` files in the repo show what you need. Copy them to the real names, fill in real values, and they'll be picked up automatically.

---

## What's reverse-engineered, what's official

**Official APIs:**
- Supabase (everything routes through Supabase)
- Withings (public REST API with OAuth 2.0)
- 17track (public REST API, free-tier API key)
- OpenAI (BioChecha calls gpt-4o-mini)
- Fastmail JMAP (used for inbox scanning — Fastmail's JMAP is public)

**Reverse-engineered:**
- **8sleep**. There's no official 8sleep API. The integration uses their iOS app's OAuth flow with a baked-in `client_id`/`client_secret` and the same endpoints the iOS app hits. **It can break at any time when 8sleep ships a new app.** I'll fix it when it does, but no guarantees on timing. If 8sleep would just publish an API I'd happily use that instead.

If you're nervous about reverse-engineered API stability, skip the 8sleep integration. The rest of The Perch works fine without it.

---

## Trademarks & disclaimers

The Perch interoperates with several third-party services. Their names appear in this codebase for technical clarity (which API are we calling?) but no endorsement, partnership, or affiliation is implied:

- **Withings** is a trademark of Withings SA.
- **8sleep / Eight Sleep** is a trademark of Eight Sleep Inc.
- **17track** is operated by 17track.net.
- **Fastmail / JMAP** is operated by Fastmail Pty Ltd.
- **Karakeep** is an open-source bookmark manager.
- **Supabase** is operated by Supabase Inc.

This project is not affiliated with, endorsed by, or sponsored by any of the above. It is a personal hobby project that talks to their public (or in 8sleep's case, undocumented) APIs as any user's own iOS app would.

---

## License

MIT. See [`LICENSE`](LICENSE). TL;DR: do whatever, don't sue me, attribution is nice but not required.

---

## Contributing

I'm not actively looking for contributions, but I'll happily merge:

- Bug fixes (especially when 8sleep breaks)
- New cards for the Today tab (follow the `HomeCardType` pattern)
- New agent integrations (follow the existing `agents/health-integrations/` shape)
- Doc/typo fixes
- Performance work (always welcome)

Open an issue first if you're going to do anything bigger than a single file. The architecture has opinions; let's make sure ours line up before you spend an afternoon on it.

---

## Credits

Built with [Claude Code](https://claude.com/claude-code) + a fair amount of stubbornness. The orders pipeline alone went through a four-attempt swipe-gesture rabbit hole before retreating to the long-press menu — there's a [design spec](docs/superpowers/specs/2026-04-27-orders-corrections-and-rules-design.md) for it.

If you make something interesting on top of this, send me a screenshot. I'm at me@hellofabio.com.
