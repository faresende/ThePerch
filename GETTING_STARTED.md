# The Perch — Getting Started

> **New to The Perch?** The full, up-to-date install guide lives in [SHARE.md](./SHARE.md). This file is a short sketch; follow SHARE.md for the real flow.

## The 60-second summary

The Perch is an iOS dashboard app backed by your own Supabase project. You run the app, point it at your Supabase, and then write data into that Supabase from any agent you like — OpenClaw, Claude Code, or plain scripts. The app displays what you feed it.

## Three setup chunks

1. **Supabase** (~5 min) — create a project, copy your URL + anon key + service role key.
2. **iOS app** (~5 min) — clone the repo, open in Xcode, run it, paste your Supabase URL + anon key into onboarding.
3. **Skills** (~10–20 min depending on how many) — pick which `skill/perch-*` directories you want, drop them into your agent runtime, set env vars, push a test record.

See [SHARE.md](./SHARE.md) for detailed steps and three different paths (just-the-app / full self-host / agent-guided).

## Project structure

```
ThePerch/
├── README.md            Top-level overview
├── SHARE.md             Canonical install guide
├── AGENT_BOOTSTRAP.md   Paste-to-your-agent setup prompt
├── GETTING_STARTED.md   ← you are here
├── ios/                 SwiftUI app (Xcode project)
├── skill/               10 modular skills, each with INSTALL.md + CONTRACT.md
├── supabase/            Schema migrations + demo seed
├── backend/             Self-host backend guide
└── docs/                Additional docs and archived historical design notes
```

## Then what?

- **Add more skills** over time. Each one has its own `INSTALL.md`.
- **Write your own skill.** Copy an existing skill's structure and follow the Supabase contract described in its `CONTRACT.md`.
- **Stuck?** Open an issue describing what you tried and where it broke.
