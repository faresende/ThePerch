# The Perch

**A personal life dashboard for iOS, driven by your own agents.**

The Perch is a native iOS app that shows your daily life at a glance — sleep and health, upcoming events, packages in transit, meals, workouts, bookmarks, anything you decide to feed it — pulled from a Supabase backend you own. Any coding agent (OpenClaw, Claude Code, plain scripts) can write data into it.

| | |
|---|---|
| **Status** | Personal project, opening up for others to try |
| **Platforms** | iOS 17+ (iPhone, widgets, Live Activities) |
| **Backend** | Supabase (self-hosted on their free tier — you own it) |
| **Data-writer agents** | Any — OpenClaw, Claude Code, or your own scripts |

---

## Is this for you?

The Perch is a good fit if you:
- want a **private** life dashboard you fully control,
- are comfortable **running your own Supabase project** (the free tier is enough),
- have (or want) a **coding agent** that can send data to that Supabase,
- want to mix and match what the dashboard shows — you **pick only the skills you want**.

It is **not** a good fit if you want a polished commercial app you can install from the App Store today. That might come later.

---

## How it works

```
Your agent           Your Supabase             The Perch (iOS)
  (any)    ────────▶   (dashboard_records,  ────▶   Cards, widgets,
                        orders, shipments)          Live Activities
```

1. You run a Supabase project — the free tier works.
2. You install the iOS app on your phone (build from source today; TestFlight later).
3. You pick which **skills** you want (health? bookmarks? deliveries?) and drop them into your agent runtime.
4. Your agent writes data. Your iOS app reads it and shows it.

Nothing leaves your Supabase — there's no The-Perch server. You're the host.

---

## Start here

| If you want to... | Read this |
|---|---|
| Understand the whole picture and get it running | [SHARE.md](./SHARE.md) |
| Hand setup off to your coding agent | [AGENT_BOOTSTRAP.md](./AGENT_BOOTSTRAP.md) |
| See what a finished install looks like | [GETTING_STARTED.md](./GETTING_STARTED.md) |

---

## The skill ecosystem

Each skill is a self-contained directory under [`skill/`](./skill) that describes one feature — the Supabase contract, how to wire a data source in, and how to install it into OpenClaw, Claude Code, or use its scripts directly. Pick only what you need.

| Skill | What it powers | Needs |
|---|---|---|
| [`perch-supabase`](./skill/perch-supabase) | **Foundation** — schema, RLS, auth | Supabase project |
| [`perch-ios`](./skill/perch-ios) | **The iOS app itself** — architecture, build, theme | macOS + Xcode |
| [`dashboard-sync`](./skill/dashboard-sync) | Core tool: `dashboard_push`, `dashboard_query`, `dashboard_heartbeat` | Service role key |
| [`perch-bookmarks`](./skill/perch-bookmarks) | Link saving + tagging | — |
| [`perch-calendar`](./skill/perch-calendar) | Calendar events → Supabase | Any ICS/CalDAV source (reference: `icalBuddy` on macOS) |
| [`perch-health`](./skill/perch-health) | Sleep, HRV, body metrics | Any sleep source (reference: Oura Ring API) |
| [`perch-nutrition`](./skill/perch-nutrition) | Meals + macros | Any meal tracker |
| [`perch-orders`](./skill/perch-orders) | Commerce emails → tracked orders | Any JMAP/IMAP email source (reference: Fastmail JMAP) |
| [`perch-deliveries`](./skill/perch-deliveries) | Orders tab + Home Deliveries + Live Activities | — |
| [`perch-workouts`](./skill/perch-workouts) | Pull/push/legs log | — |

All skills share the same Supabase contract. You can start with `perch-supabase` + `perch-ios` + one feature skill, and add more later.

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
├── docs/                Guides and archived historical design docs
└── README.md            ← you are here
```

---

## Status and expectations

This was built for one person. Opening it up is an experiment. Expect:

- Rough edges, especially outside the golden path the author actually uses.
- Docs that still assume some familiarity with Supabase, iOS, and coding agents.
- No support guarantee. Issues and PRs welcome once the repo is public.

If something's broken or confusing, the most useful thing you can do is open an issue describing what you tried and where it fell over.

---

## License

TBD — a permissive open-source license will be added before the repo goes public.
