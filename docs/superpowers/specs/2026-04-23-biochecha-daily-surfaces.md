# BioChecha daily surfaces in The Perch

**Date:** 2026-04-23
**Status:** Scaffolded (iOS + contracts); BioChecha-side prompts queued for wiring.

Fábio currently gets two kinds of information from BioChecha on Telegram: a daily briefing (too much, often ignored) and ad-hoc macro reminders. The ask is to surface both in the Today tab as at-a-glance cards, and to add a **smart workout hint** that looks at recent training history.

## Two new record shapes

### 1. `daily_briefing`
A scannable summary of the morning — whatever BioChecha would have said on Telegram, distilled into a fixed shape the iOS app can render.

```
category = "health"
type     = "daily_briefing"
display_hint = "daily_briefing"
agent_id = "biochecha"
title    = "Wed Apr 23"               -- short, human-readable
data: {
  date:        "2026-04-23",
  headline:    "Strong recovery after yesterday's push day.",
  highlights:  [
    { icon: "❤️",  label: "HRV 62 ms",    trend: "up",   detail: "+8 vs 7d avg" },
    { icon: "💤", label: "Sleep 7h 42m", trend: "steady", detail: "83% score" },
    { icon: "⚖️",  label: "82.1 kg",      trend: "steady", detail: "-0.1 vs week" },
    { icon: "🎯", label: "Training day",  trend: null,    detail: "2900 kcal target" }
  ],
  action_items: [
    { text: "Hit protein by 1pm (behind pace).", priority: "medium" },
    { text: "Scar cream tonight.", priority: "low" }
  ],
  recovery_rating: "green" | "yellow" | "red",
  generated_at: "2026-04-23T06:00:00+01:00"
}
```

Only `date`, `headline`, and `generated_at` are required. Everything else optional — the iOS card renders what's there and hides the rest.

### 2. `workout_hint`
Suggestion for today's training based on the last 7 days of workouts.

```
category = "health"
type     = "workout_hint"
display_hint = "workout_hint"
agent_id = "biochecha"
title    = "Next: Push day"
data: {
  date:         "2026-04-23",
  suggested_type: "push",             -- pull | push | legs | rest
  reasoning:    "Legs Monday, pull Tuesday, rest Wednesday. Ready for push.",
  last_7d: {
    pull:  { count: 1, last_date: "2026-04-22" },
    push:  { count: 1, last_date: "2026-04-20" },
    legs:  { count: 1, last_date: "2026-04-21" },
    rest:  { count: 2 }
  },
  flags: [
    { kind: "muscle_gap",    detail: "Back hasn't been worked in 5 days." },
    { kind: "volume_trend",  detail: "Weekly volume up 12% vs previous week." }
  ],
  generated_at: "2026-04-23T06:00:00+01:00"
}
```

`suggested_type` + `reasoning` are the load-bearing fields. `flags` is where BioChecha can surface anything noteworthy (skipped muscle group, overtraining risk, PR-adjacent sets).

Both shapes are versioned by the `display_hint` string — if we change them later, add `_v2` and the iOS decoder falls back cleanly to the older decoder.

## iOS consumption

- `DashboardViewModel` already filters by category. Adds two computed
  properties: `latestDailyBriefing` and `latestWorkoutHint`, each returning
  the most recent record of its `display_hint`.
- Two new cards under `Views/Cards/`: `DailyBriefingCard`, `WorkoutHintCard`.
- `HomeCardOrdering` inserts both at the top of the Today tab, above the
  existing chips and deliveries card.
- Empty states: if no record exists (BioChecha hasn't run yet today), the
  card shows a quiet placeholder ("BioChecha hasn't reported in yet") with
  no error styling.

## BioChecha-side work (queued)

BioChecha's `biochecha-morning-recomp-macros` cron runs daily. Extend its
prompt so at the end of each run it writes BOTH records via the existing
`dashboard_push` skill. Contract details live in this spec; the prompt
appended to the cron payload says: "After your normal work, write one
`daily_briefing` and one `workout_hint` per the contract at
`docs/superpowers/specs/2026-04-23-biochecha-daily-surfaces.md`."

That change isn't landing in this session — it's a prompt edit that belongs
to the workspace repo's cron payload, queued for your review.

## What lives where

| Piece | Repo | Status |
|---|---|---|
| Record contract (this doc) | ThePerch | Shipping |
| `DailyBriefingCard.swift`, `WorkoutHintCard.swift` | ThePerch | Shipping |
| `DashboardViewModel` additions | ThePerch | Shipping |
| `HomeCardOrdering` update | ThePerch | Shipping |
| BioChecha cron prompt extension | `~/.openclaw/cron/jobs.json` | **Queued** — you flip it when you're ready to trial |

## Migration / rollout

1. Land the iOS side. Cards show "not yet reported" until data arrives.
2. Manually insert one hand-crafted `daily_briefing` + `workout_hint` row to confirm rendering.
3. Extend BioChecha's morning prompt.
4. Observe for a week. Iterate on the record shape if BioChecha keeps
   producing fields we didn't predict.

Low risk. Cards degrade gracefully.
