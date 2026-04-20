# Installing `dashboard-sync`

Core agent tool: dashboard_push, dashboard_query, dashboard_heartbeat. Install this if any other perch-* skill is installed.

Pick the block that matches your agent runtime. All three paths use the same underlying files — the difference is only where the runtime looks for them.

---

## OpenClaw

```bash
cp -r skill/dashboard-sync ~/.openclaw/skills/
```

Then set the env vars below in your OpenClaw agent's environment (`~/.openclaw/secrets.json`, your shell profile, or a per-agent env file — whichever you use).

## Claude Code

```bash
mkdir -p ~/.claude/skills && cp -r skill/dashboard-sync ~/.claude/skills/
```

Claude Code reads `SKILL.md` as the skill definition. Set the env vars in your shell or in a project-local `.env` that your Claude Code session can read.

## Plain CLI / bring your own agent

```bash
cd skill/dashboard-sync
# For skills with scripts/:
[ -f package.json ] && npm install
# Run scripts directly; see SKILL.md for the specific entry points.
```

Use `SKILL.md` as a prompt you give to any LLM via their tool-use API, and call the scripts yourself. No runtime dependency.

---

## Required environment

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `PERCH_USER_ID (recommended fallback)`

## Other prerequisites

- Node 18+ and npm (for the TypeScript tools)

## What this skill writes

- Writes go to **dashboard_records + records + agents + token_usage** with `category=(all — this is the generic writer)` and `type` in `(all)`.

Full contract: [`CONTRACT.md`](./CONTRACT.md).
