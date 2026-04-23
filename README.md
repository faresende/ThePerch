# The Perch

**A personal life dashboard for iOS, driven by your own agents.**

The Perch is a native iOS app that shows your day at a glance (sleep, health, upcoming events, packages in transit, meals, workouts, bookmarks, whatever you want to feed it) from a Supabase backend you own. Any coding agent you trust (OpenClaw, Claude Code, a cron'd bash script) can write into it. If you don't trust any of them, this probably isn't for you.

| | |
|---|---|
| **Status** | Personal project, now opening up for others to try. Expect dust. |
| **Platforms** | iOS 17+ (iPhone, widgets, Live Activities) |
| **Backend** | Supabase on their free tier. You own it, you run it, it's your problem. |
| **Data-writer agents** | Whatever you've got: OpenClaw, Claude Code, your own scripts, a clever intern |

---

## Is this for you?

The Perch is a good fit if you:
- want a **private** life dashboard you fully control,
- are comfortable **running your own Supabase project** (free tier is plenty),
- have (or want) a **coding agent** that can write to it,
- want to pick and choose what shows up. **You install only the skills you want.**

It's **not** a good fit if you want a polished App Store app you can install today. That might come later. Today this is "clone it and run Xcode." If that sentence made you twitch, bookmark the repo and check back in six months.

---

## How it works

```
Your agent           Your Supabase             The Perch (iOS)
  (any)    ────────▶   (dashboard_records,  ────▶   Cards, widgets,
                        orders, shipments)          Live Activities
```

1. You spin up a Supabase project. Free tier is fine.
2. You install the iOS app on your phone (build from source today, TestFlight later).
3. You pick which **skills** you want (health, bookmarks, deliveries, etc.) and drop them into your agent runtime.
4. Your agent writes data. Your app reads it. That's the whole loop.

There is no The-Perch server. Your data sits in your Supabase. I can't see it and neither can anyone else. That's not a marketing claim, it's just that I never built the server that would let me.

---

## Start here

| If you want to... | Read this |
|---|---|
| Understand the whole thing and get it running | [SHARE.md](./SHARE.md) |
| Hand the setup to your coding agent | [AGENT_BOOTSTRAP.md](./AGENT_BOOTSTRAP.md) |
| See what a finished install looks like | [GETTING_STARTED.md](./GETTING_STARTED.md) |

---

## The skill ecosystem

Each skill is a self-contained directory under [`skill/`](./skill) that covers one feature: the Supabase contract, how to wire a data source, and how to install it into OpenClaw, Claude Code, or just run the scripts directly. Install only what you want. Nobody needs all ten on day one.

| Skill | What it powers | Needs |
|---|---|---|
| [`perch-supabase`](./skill/perch-supabase) | **Foundation.** Schema, RLS, auth. | Supabase project |
| [`perch-ios`](./skill/perch-ios) | **The iOS app itself.** Architecture, build, theme. | macOS + Xcode |
| [`dashboard-sync`](./skill/dashboard-sync) | Core tool: `dashboard_push`, `dashboard_query`, `dashboard_heartbeat`. | Service role key |
| [`perch-bookmarks`](./skill/perch-bookmarks) | Link saving + tagging. | nothing extra |
| [`perch-calendar`](./skill/perch-calendar) | Calendar events into Supabase. | any ICS/CalDAV source. I use `icalBuddy` on macOS because it's ugly and it works. |
| [`perch-health`](./skill/perch-health) | Sleep, HRV, body metrics. | any sleep source. I use the Oura Ring API. |
| [`perch-nutrition`](./skill/perch-nutrition) | Meals + macros. | any meal tracker |
| [`perch-orders`](./skill/perch-orders) | Commerce emails into tracked orders. | any JMAP/IMAP source. I use Fastmail JMAP. Gmail works too, I just refuse. |
| [`perch-deliveries`](./skill/perch-deliveries) | Orders tab, Home Deliveries, Live Activities. | nothing extra |
| [`perch-workouts`](./skill/perch-workouts) | Pull/push/legs log. | nothing extra |

All skills share the same Supabase contract. A reasonable starting shape is `perch-supabase` + `perch-ios` + one feature skill. Add more whenever. You're not being graded.

---

## What's in this repo

```
ThePerch
├── ios/                 The SwiftUI app (Xcode project)
├── skill/               10 modular skills (see table above)
├── supabase/            Schema migrations + demo seed data
├── backend/             Self-host backend guide
├── web/                 Supporting web assets
├── scripts/             Reference helper scripts
├── docs/                Guides, and some archaeology from earlier design passes
└── README.md            (you are here)
```

---

## Status and expectations

I built this for myself. Opening it up is an experiment. Expect:

- Rough edges, especially outside the golden path I actually use day to day.
- Docs that assume some comfort with Supabase, iOS, and coding agents. "What's a JWT" is a question I can't answer for you in a README.
- No support guarantee. Issues and PRs are welcome once the repo is public. DMs are not.

If something's broken or confusing, the most useful thing you can do is open an issue describing what you tried and where it fell over. "It doesn't work" is not a bug report, it's a haiku.

---

## License

[MIT](./LICENSE). Fork it, remix it, ship it. Attribution is nice but not required. Making money off a renamed clone is legal, just a bit sad.
