# Installing `perch-supabase`

The foundational skill: Supabase schema, RLS, auth, service-role setup. Read this first.

Pick the block that matches your agent runtime. All three paths use the same underlying files — the difference is only where the runtime looks for them.

---

## OpenClaw

```bash
cp -r skill/perch-supabase ~/.openclaw/skills/
```

Then set the env vars below in your OpenClaw agent's environment (`~/.openclaw/secrets.json`, your shell profile, or a per-agent env file — whichever you use).

## Claude Code

```bash
mkdir -p ~/.claude/skills && cp -r skill/perch-supabase ~/.claude/skills/
```

Claude Code reads `SKILL.md` as the skill definition. Set the env vars in your shell or in a project-local `.env` that your Claude Code session can read.

## Plain CLI / bring your own agent

```bash
cd skill/perch-supabase
# For skills with scripts/:
[ -f package.json ] && npm install
# Run scripts directly; see SKILL.md for the specific entry points.
```

Use `SKILL.md` as a prompt you give to any LLM via their tool-use API, and call the scripts yourself. No runtime dependency.

---

## Required environment

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_ANON_KEY`

## Other prerequisites

- A Supabase project (free tier is enough)

## What this skill writes

- Writes go to **(all — this skill is the schema itself)** with `category=(all)` and `type` in `(all)`.

Full contract: [`CONTRACT.md`](./CONTRACT.md).
