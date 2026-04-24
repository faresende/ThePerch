# Installing `perch-deliveries`

Two-pipeline delivery tracking with Live Activities. Reads orders + shipments; projects to dashboard_records for the Home card.

Pick the block that matches your agent runtime. All three paths use the same underlying files — the difference is only where the runtime looks for them.

---

## OpenClaw

```bash
cp -r skill/perch-deliveries ~/.openclaw/skills/
```

Then set the env vars below in your OpenClaw agent's environment (`~/.openclaw/secrets.json`, your shell profile, or a per-agent env file — whichever you use).

## Claude Code

```bash
mkdir -p ~/.claude/skills && cp -r skill/perch-deliveries ~/.claude/skills/
```

Claude Code reads `SKILL.md` as the skill definition. Set the env vars in your shell or in a project-local `.env` that your Claude Code session can read.

## Plain CLI / bring your own agent

```bash
cd skill/perch-deliveries
# For skills with scripts/:
[ -f package.json ] && npm install
# Run scripts directly; see SKILL.md for the specific entry points.
```

Use `SKILL.md` as a prompt you give to any LLM via their tool-use API, and call the scripts yourself. No runtime dependency.

---

## Required environment

_None required beyond what your runtime needs to reach Supabase._

## Other prerequisites

_None._

## What this skill writes

- Writes go to **orders + shipments (primary) and dashboard_records (legacy card)** with `category=deliveries` and `type` in `order`, `shipment`, `delivery`.

Full contract: [`CONTRACT.md`](./CONTRACT.md).
