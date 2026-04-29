# Contributing

This is a personal project shaped like a public repo. PRs are welcome but the bar is "do you also want this exact thing." A few notes so we both spend our time well.

## What I'll merge readily

- **Bug fixes** — especially when 8sleep ships a new app and the integration breaks
- **Doc/typo fixes** — always
- **New agent integrations** — follow the existing `agents/health-integrations/` shape (a Python script, env-driven, idempotent upserts via `bulk_upsert_health_metrics`)
- **New cards on the Today tab** — follow the `HomeCardType` enum + `HomeCardOrdering`
- **Performance fixes** — there's already a perf audit's worth of deferred wins in the commit history; pick one if you want

## Open an issue first if

- You're proposing anything bigger than a single file
- You want to change the architecture (the parts in `docs/superpowers/specs/` represent decisions I've already made and don't want to relitigate)
- The change touches the corrections-and-rules engine — Phases 1 + 2 are shipped (capture layer + auto-promoted `merchant_rules`), Phase 3 (LLM low-confidence fallback) is still deferred and I want to make sure new work doesn't paint that path into a corner

## Style notes

- Swift: standard SwiftUI conventions. View-builder bodies. State on the view-model, not the view. `@Observable` over `@Published`.
- TypeScript: existing patterns. The `dashboard-sync` skill has its own conventions — match them.
- Python: the agent scripts are stdlib-only by deliberate choice (no `requests`, no `pydantic`). Keep it that way unless the dependency genuinely earns its place.
- Commit messages: present tense, lowercased prefix (`fix(orders):`, `feat(today):`), wrapped to 72 chars. The recent commit history is a good reference.
- No emoji in code or commit messages. Emoji in user-facing copy is allowed when earned.

## Setup for local dev

See [`SETUP-FOR-AGENTS.md`](SETUP-FOR-AGENTS.md) (an LLM agent can run it for you) or [`docs/INSTALL.md`](docs/INSTALL.md) (slow path, by hand). Either way, you'll need your own Supabase project — there's no shared backend.

## What I won't merge

- Anything that adds telemetry / analytics / phone-home behavior
- Hosted-service abstractions (this is self-hosted by design — see Architecture in the README)
- Subscriptions, paywalls, freemium tiering — same reason
- Theme rewrites that aren't Editorial Linen (the design system is opinionated; that's the point)

## Reporting security issues

See [`SECURITY.md`](SECURITY.md). Don't open public issues for security stuff.
