# Installing `perch-orders`

Email → orders + shipments pipeline using content-based detection.

Pick the block that matches your agent runtime. All three paths use the same underlying files — the difference is only where the runtime looks for them.

---

## OpenClaw

```bash
cp -r skill/perch-orders ~/.openclaw/skills/
```

Then set the env vars below in your OpenClaw agent's environment (`~/.openclaw/secrets.json`, your shell profile, or a per-agent env file — whichever you use).

## Claude Code

```bash
mkdir -p ~/.claude/skills && cp -r skill/perch-orders ~/.claude/skills/
```

Claude Code reads `SKILL.md` as the skill definition. Set the env vars in your shell or in a project-local `.env` that your Claude Code session can read.

## Plain CLI / bring your own agent

```bash
cd skill/perch-orders
# For skills with scripts/:
[ -f package.json ] && npm install
# Run scripts directly; see SKILL.md for the specific entry points.
```

Use `SKILL.md` as a prompt you give to any LLM via their tool-use API, and call the scripts yourself. No runtime dependency.

---

## Required environment

- `JMAP/IMAP credentials for your email provider (reference: Fastmail JMAP)`

## Other prerequisites

- A JMAP- or IMAP-accessible mailbox. Reference adapter: Fastmail JMAP.

## What this skill writes

- Writes go to **orders + shipments** with `category=deliveries / commerce` and `type` in `order`, `shipment`.

Full contract: [`CONTRACT.md`](./CONTRACT.md).
