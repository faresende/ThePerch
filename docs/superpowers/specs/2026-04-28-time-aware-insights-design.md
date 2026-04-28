# Time-Aware BioChecha Insights — Design Spec

**Date:** 2026-04-28
**Status:** Approved, executing

## Motivation

The existing morning BioChecha insight is generated at 7am Lisbon and reflects the prior 24h. By noon it's stale; by afternoon it's an artifact. The user wants insights that evolve through the day — anticipatory ("protein shake before your meeting block"), opportunistic ("rest day + calendar gap = walk"), logistical ("Body & Fit out for delivery, between 1-3pm"), and reflective.

This spec adds three more scheduled insight slots plus an event-driven slot, all rendering through the same `DailyInsightCard` (single rotating slot — no new UI surface). Voice and aesthetic stay identical to the morning insight.

## Architecture

```
4 scheduled cron jobs (07:00 / 12:00 / 15:00 / 20:00 Lisbon)
       +
1 event hook (17track poll detects status flip → out_for_delivery, or ETA → today)
       ↓
biochecha_dynamic_insight.py <slot>
       ↓
1. Gather AppState (today's meals/targets/calendar/orders + recent sleep/body comp + workout schedule)
2. Score eligible categories for this slot → pick winner
3. Pack fact bundle (specific data points the LLM gets)
4. LLM writes 30-55 words in slot-specific voice (existing BioChecha SYSTEM_PROMPT + slot addendum)
5. Upsert to public.insights with slot-specific insight_type
       ↓
public.insights (insight_type = daily_health_{slot} | event_logistics)
       ↓
iOS DailyInsightCard reads most-recent-today insight matching `daily_health_*` OR `event_logistics`
```

**Single-slot promise:** at any moment, exactly one BioChecha insight is visible at the top of the Today tab. New generations replace older ones from the same day in the iOS query (most-recent-today wins).

## Slot definitions

| Slot | Time | Purpose | Eligible category playlist |
|---|---|---|---|
| **Morning** | 07:00 | Reflect on overnight + frame today | reflective, anomaly, anticipatory_broad |
| **Midday** | 12:00 | Pre-afternoon checkpoint | anticipatory_lunch_window, goal_pacing_*, logistics_arriving_today |
| **Afternoon** | 15:00 | Gap-aware opportunity | opportunistic_*, goal_pacing_*, logistics_*, anomaly |
| **Evening** | 20:00 | Day recap + tomorrow preview | recap_day, behavioral_*, reflective_evening, anticipatory_tomorrow |
| **event_logistics** | (event) | Real-time package update | logistics_event_out_for_delivery, logistics_event_eta_today |

Categories outside a slot's playlist score 0 for that slot.

## Categories (v1)

Nine concrete categories. Each is a small Python class implementing `score(state) -> Optional[CategoryResult]`.

| Category | Triggers high when… |
|---|---|
| `reflective_morning` | morning slot — base score 0.5 always; bumped by clear pattern in last 7 days (sleep trend, weight drift, protein streak) |
| `reflective_evening` | evening slot — analogous, looking back at the day |
| `anomaly_recent_pattern` | any slot, scaled by deviation magnitude (3+ short nights, dinner logged unusually late, HRV climbing N days) |
| `anticipatory_lunch_window` | midday + ≥2 calendar events in next 4h + calories <40% target + before 14:00 |
| `anticipatory_broad` | morning, scaled by what's coming (multi-meeting day, workout scheduled, etc.) |
| `anticipatory_tomorrow` | evening — tomorrow has notable load (early meeting, workout) and today's recovery state matters |
| `goal_pacing_protein` | midday/afternoon, scaled by `(target - consumed) / target` × `meals_remaining` |
| `goal_pacing_calories` | midday/afternoon, similar shape but different threshold rules (deficit vs maintenance) |
| `goal_pacing_steps` | afternoon — when steps are <70% of typical-for-this-hour |
| `logistics_arriving_today` | midday/afternoon — any shipment with ETA today, not delivered |
| `logistics_event_out_for_delivery` | event slot — fires when 17track polling detects status flip |
| `logistics_event_eta_today` | event slot — fires when ETA changes from `>1 day away` to `today` |
| `opportunistic_walk` | afternoon + workout=`rest`/`light` + ≥45min calendar gap + steps <70% typical |
| `opportunistic_workout` | afternoon — same shape but for missed-workout-this-week + free gap + non-rest day |
| `behavioral_capture_gap` | any slot, scales when hours-since-last-meal-logged >18h |
| `recap_day` | evening — always 1.0 score (it's the slot's purpose); fact bundle changes daily |

Easy to add more in Phase 2 — each is an isolated function over `AppState`.

## Rule engine

**`AppState` snapshot** is gathered once per slot run:

```python
@dataclass
class AppState:
    slot: SlotKind
    now: datetime
    today_meals: list[Meal]
    today_targets: NutritionTargets
    today_calendar_remaining: list[CalendarEvent]   # next ~6h
    today_orders_in_transit: list[OrderWithShipment]
    sleep_last_7: list[SleepNight]
    body_comp_last_30: list[BodyComp]
    workout_schedule_today: WorkoutKind  # rest | light | training | unknown
    avg_steps_last_7_at_this_hour: int   # baseline for "behind today"
    event_trigger: Optional[EventTrigger]  # only set for event slot
```

**Ranker:**

```python
results = [c.score(state) for c in CATEGORIES if c.eligible_for(state.slot)]
non_null = [r for r in results if r is not None]
winner = max(non_null, key=lambda r: (r.score, -CATEGORY_PRIORITY[r.category]))
```

**Static priority order** for tie-breaks (highest first):
`logistics_event > logistics > opportunistic > anticipatory > goal_pacing > anomaly > behavioral > recap > reflective`

Logistics events win ties because they're the most time-sensitive.

**Fallback** when winner.score < 0.3: emit a "quiet day" insight using a dedicated fact bundle. Voice prompt: *"Quiet data day. Nothing pulling either way. Acknowledge briefly — no manufactured drama."*

## Slot-specific voice prompts

All inherit the existing BioChecha SYSTEM_PROMPT (no clichés, comparative > absolute, mix domains, 30-55 words). Each slot adds a focus line:

| Slot | Voice addendum |
|---|---|
| Morning | "Reflect on overnight + recent. Frame what's coming today — gently, not as instruction." |
| Midday | "What's worth noticing now, before the afternoon. Anticipatory > retrospective." |
| Afternoon | "Pick the most pressing thing right now — gap, opportunity, package, pacing. Direct, present-tense." |
| Evening | "Recap the day in 30 words. Tomorrow's setup if useful. No exclamation, no 'you did great'." |
| event_logistics | "Lead with the event. The fact is the headline. One line, maybe two." |

The fact bundle from the rule engine constrains *what* the insight is about; the voice prompt constrains *how* it's said. The LLM's job is the prose.

## Event-driven slot

**Triggers (v1):**
1. 17track polling detects shipment status flip to `out_for_delivery`
2. 17track polling detects shipment ETA change from `>1 day away` to `today`

**Integration point:** `pollAndUpdateShipment` in `skill/dashboard-sync/src/orders-autopilot.ts` gains a small post-update branch:

```typescript
if (statusFlippedToOutForDelivery || etaJustBecameToday) {
  fireEventInsight({
    kind: statusFlippedToOutForDelivery ? 'out_for_delivery' : 'eta_today',
    shipment, oldStatus, newStatus, oldEta, newEta,
  });  // fire-and-forget; don't block the polling loop
}
```

`fireEventInsight` invokes `biochecha_event_insight.py` (a thin wrapper around `biochecha_dynamic_insight.py` that constructs the `event_trigger` payload and calls with `slot=event_logistics`).

**Don't-churn guard:** before generating, the script checks:
- Most recent insight for today is older than 30 min, AND
- That insight isn't already covering the same logistics topic (same `shipment_id` in fact bundle)

If both true → generate. Otherwise → skip silently.

**Cadence ceiling:** at most ~3-5 event insights per busy week. The 17track poll runs every 30 min so no more than ~48 chances per day to fire, and most polls don't show status changes.

## iOS

Three changes, all small:

1. **`InsightsService.fetchTodayDailyInsight()`**: change query from `eq.insight_type=daily_health` to filtering on `insight_type IN (daily_health_morning, daily_health_midday, daily_health_afternoon, daily_health_evening, event_logistics)` (or PostgREST's `like.daily_health_%` plus `eq.event_logistics` union). Order by `generated_at desc` limit 1.

2. **`Insight.kind` enum** (in `Models/Insight.swift`) gains: `dailyHealthMorning`, `dailyHealthMidday`, `dailyHealthAfternoon`, `dailyHealthEvening`, `eventLogistics`. The kicker computed property returns `"TODAY · BIOCHECHA"` for all of them — same as today.

3. **`DailyInsightCard`**: no change. Renders whatever the most-recent insight body is.

**No visual differentiation per slot in v1.** The existing timestamp on the right of the kicker (e.g. *"2:14pm"*) is enough cue that the insight is current. If slots blur together later we add a subtle slot label or color cue then.

## Cron

```
07:00  biochecha-morning-insight    (rename of existing biochecha-daily-insight)
12:00  biochecha-midday-insight     (new)
15:00  biochecha-afternoon-insight  (new)
20:00  biochecha-evening-insight    (new)
```

All four call `python3 ~/.openclaw/workspace/scripts/health-integrations/biochecha_dynamic_insight.py <slot>`. Existing 7am cron is renamed and its message updated.

Event-driven slot has no cron entry — it piggy-backs on the existing 17track polling cron (every 30 min).

## Migration

Single SQL statement, idempotent:

```sql
UPDATE public.insights
SET insight_type = 'daily_health_morning'
WHERE insight_type = 'daily_health' AND agent_id = 'biochecha';
```

iOS fetch query change deploys with the same TestFlight build. No downtime — old kind values keep working until the rename runs (the new query matches them via `like daily_health_%`).

## Cost

| Source | Calls/day | Cost/day |
|---|---|---|
| Scheduled (4 slots) | 4 | $0.0004 |
| Event-driven (busy week) | 1-3 extra | $0.0001-$0.0002 |
| Quiet days | 4 (some land on fallback "quiet" prompt — same call count) | $0.0004 |

Annual ceiling: <$0.20.

## Data flow examples

**Example 1: Midday slot, busy afternoon, low protein**

```
12:00 cron fires biochecha_dynamic_insight.py midday
  → AppState: 3 calendar events 14:00-17:00, protein 35g of 180g target, 1 meal logged
  → score:
      anticipatory_lunch_window → 0.92 (matches all conditions)
      goal_pacing_protein → 0.78
      logistics_arriving_today → 0.0 (no shipments)
  → winner: anticipatory_lunch_window
  → fact_bundle: {events_in_window: 3, protein_deficit_g: 145, meals_remaining: 4}
  → LLM (midday voice): "Three meetings stacked 2-5. Protein's at 35g — half a salmon
     bowl now puts you on pace." (32 words)
  → insert into insights, insight_type=daily_health_midday
```

**Example 2: Afternoon slot, rest day, calendar gap**

```
15:00 cron fires biochecha_dynamic_insight.py afternoon
  → AppState: workout=rest, next event 17:30, current 15:02 (148min gap),
              steps 4,200 vs typical 6,800 by this hour
  → score:
      opportunistic_walk → 0.95
      goal_pacing_steps → 0.71
      logistics_arriving_today → 0.0
  → winner: opportunistic_walk
  → fact_bundle: {gap_min: 148, next_event: "design review 17:30", steps_deficit: 2600}
  → LLM (afternoon voice): "Two and a half hours before design review. Step count's
     short of where it usually is by now. Walk's the obvious move." (28 words)
```

**Example 3: Event slot, Body & Fit hits out-for-delivery**

```
14:47 17track polling cron sees Body&Fit shipment flip to out_for_delivery
  → calls fireEventInsight({kind: out_for_delivery, shipment, ...})
  → most recent today insight: 12:00 midday, covers protein/lunch — different topic ✓
  → fires biochecha_event_insight.py
  → AppState (with event_trigger populated)
  → score: logistics_event_out_for_delivery → 1.0 (event slot, exact match)
  → fact_bundle: {merchant: "Body & Fit", carrier: "DHL", window: "today", current_time: "14:47"}
  → LLM (event voice): "Body & Fit just hit out-for-delivery. Likely landing late
     afternoon." (12 words)
  → insert into insights, insight_type=event_logistics
```

## Out of scope (Phase 2 / 3)

- **Calendar-gap detection as a real-time event trigger** — would need a separate calendar-watching cron + EventKit event stream. The 3pm scheduled slot already covers gap-aware insights with up to 5h latency.
- **Push notifications / system alerts**
- **Multi-card surfaces** (parallel insight cards for different categories)
- **User-tunable category weights** (UI to bump/demote categories)
- **Foreground-triggered regeneration** (regenerate on app open if last insight is stale)
- **A/B testing different prompts per slot**
- **Slot-specific visual differentiation** in the UI (color cue, slot label) — defer until needed

## Net implementation footprint

| Layer | What | Approx LOC |
|---|---|---|
| Python | `biochecha_dynamic_insight.py` + 9 category scorers + slot prompts + AppState gather | ~600 |
| Python | `biochecha_event_insight.py` thin wrapper | ~50 |
| Scanner (TS) | hook in `pollAndUpdateShipment` to fire event insight | ~30 |
| iOS | enum + service query + fetch logic | ~25 |
| Migration | SQL UPDATE | 5 lines |
| Cron | 3 new entries + 1 rename in jobs.json | n/a (config) |
| **Total** | | **~700 LOC** |

About 1.5 days of focused work.

## Future-work breadcrumbs

- **Calendar-gap real-time detection:** a small `calendar-watch` cron running every 5 min that diffs current EventKit state against last-seen, fires `event_calendar_gap_appeared` when a >1h gap opens unexpectedly.
- **Goal-at-risk alerts:** evening slot can fire an early warning if afternoon shows the user's likely to miss a target. Today this falls into `goal_pacing_*` but could escalate.
- **Cross-domain pattern surfacing:** today's `anomaly_recent_pattern` is single-domain. Phase 2 could connect dots ("4 high-protein days, 4 short-sleep nights — coincidence?"). Needs a small pattern-mining helper.
