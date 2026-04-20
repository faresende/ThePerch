# The Perch — Skill Ecosystem

This is the modular skill documentation for The Perch iOS app and its supporting backend infrastructure.

## Quick Start

**New contributor?** Read these in order:
1. [perch-supabase](./skill/perch-supabase/SKILL.md) — understand the shared database
2. [perch-ios](./skill/perch-ios/SKILL.md) — understand the app architecture
3. Then explore the feature skills below based on what you're working on

## Skill Map

```
ThePerch
├── perch-supabase     ← FOUNDATIONAL: schema, RLS, service role, all tables
├── perch-ios          ← iOS app: SwiftUI, MVVM, widgets, theme
├── perch-orders       ← Commerce email → orders + shipments pipeline
├── perch-health       ← Oura Ring + manual body metrics
├── perch-nutrition     ← Calorie/macro tracking via BioChecha
├── perch-calendar     ← Apple Calendar → Supabase events + travel detection
├── perch-bookmarks     ← Link saving + agent enrichment (Archie)
├── perch-deliveries   ← Two-pipeline delivery tracking + Live Activities
├── perch-workouts     ← Pull/push/legs training log + calendar integration
└── dashboard-sync    ← Core agent tool: dashboard_push/query/heartbeat
```

## Skills Reference

| Skill | Description |
|-------|-------------|
| **[perch-supabase](./skill/perch-supabase/)** | Database schema, RLS policies, authentication, service role, example queries |
| **[perch-ios](./skill/perch-ios/)** | iOS app architecture, project structure, build/run, theme system, widgets |
| **[perch-orders](./skill/perch-orders/)** | Fastmail JMAP email ingestion, order/shipment detection, 17track polling |
| **[perch-health](./skill/perch-health/)** | Oura Ring API, weight/body metrics, body goal trending |
| **[perch-nutrition](./skill/perch-nutrition/)** | BioChecha meal logging, macro targets, nutrition cards on iOS |
| **[perch-calendar](./skill/perch-calendar/)** | icalBuddy → Supabase events, timezone handling, travel mode |
| **[perch-bookmarks](./skill/perch-bookmarks/)** | Bookmark lifecycle, enrichment pipeline, search/filter |
| **[perch-deliveries](./skill/perch-deliveries/)** | Orders tab + Home Deliveries card, two-pipeline architecture, Live Activities |
| **[perch-workouts](./skill/perch-workouts/)** | Pull/push/legs rotation, workout logging, calendar integration |
| **[dashboard-sync](./skill/dashboard-sync/)** | Core agent tools: dashboard_push, dashboard_query, dashboard_heartbeat |

## Key Architecture Decisions

### Two-Pipeline Delivery Model
The deliveries feature uses two parallel pipelines for historical reasons. See [perch-deliveries](./skill/perch-deliveries/) for the full explanation.

### nutrition `meal_log` Known Issue
Newer nutrition rows with `type=meal` and `display_hint=meal_log` may not be handled by the generic `dashboard_push` helper. See [perch-nutrition](./skill/perch-nutrition/).

### ISO8601 Timezone Requirement
All calendar event times must include a timezone suffix. Missing timezones cause silent decoding failures and empty cards. See [perch-calendar](./skill/perch-calendar/).

## Repository

- **GitHub**: https://github.com/faresende/ThePerch
- **Live**: https://whoisthisfabio.com/ThePerch/
- **Supabase**: cgmaotzmeoiueyzlchaz.supabase.co
