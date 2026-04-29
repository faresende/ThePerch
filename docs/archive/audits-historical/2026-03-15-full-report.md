# ThePerch Production Readiness Audit — Full Report
**Date:** 2026-03-15
**Auditor:** Bancada

## Executive Summary

**105 total issues: 19 critical, 49 warnings, 37 polish**

The app has a solid foundation but is not production-ready. The main risks are:
- Crash risks from force unwraps and unsynchronized state
- Visual inconsistencies across tabs (colors, typography, spacing)
- Missing states (empty, loading, error) everywhere
- Hardcoded single-user assumptions (blocking multi-user)
- Calendar tab is functionally incomplete

## Prioritized Action Plan

### Sprint 1: Crash Prevention + Auth Foundation (1-2 days)
1. Fix all force unwraps (BackgroundRefreshService, JSONValueDecoder, AppConfig)
2. Fix CacheService/CrashReporter thread safety
3. Fix AuthViewModel task leak
4. Extract hardcoded user ID to AppConfig
5. Remove hardcoded "Fabio" from UI
6. Remove duplicate CardGalleryView file
7. Remove dead SectionViewModelProtocol
8. Add Sendable conformance to model types

### Sprint 2: Visual Consistency (1-2 days)
1. Define and enforce accent color system (amber = primary, green = success, red = error)
2. Fix macro bar colors (same colors Home + Health)
3. Standardize card border styling
4. Standardize card title typography weights
5. Fix tab bar truncation
6. Fix event title wrapping (2 lines)
7. Add card interaction affordances (chevrons, tap hints)

### Sprint 3: Missing States (1-2 days)
1. Design empty state component (icon + message + optional CTA)
2. Add empty states to every tab/section
3. Add skeleton/shimmer loading states
4. Redesign error banner (clear message, dismiss button, auto-retry)
5. Add per-card error states
6. Add stale data warnings with consistent thresholds

### Sprint 4: Calendar Upgrade (2-3 days)
1. Add day-by-day navigation (left/right arrows)
2. Add week view
3. Add upcoming events section (next 7 days)
4. Show date in section header
5. Fix timezone display for international events

### Sprint 5: Admin Safety + Polish (1 day)
1. Add confirmation dialogs for destructive actions
2. Add action result states (loading/success/failure)
3. Fix OpenClaw status with actionable resolution
4. Fix agent card descriptions and interaction affordances
5. Deduplicate "Claudinho" agents or add descriptions

### Sprint 6: Code Quality (1 day)
1. Remove ~60 debug print statements (or gate behind #if DEBUG)
2. Consolidate 3 relativeTime implementations
3. Remove DateFormatting enum (move uptimeString to PerchFormatters)
4. Remove dead updateHomeWidgets no-op
5. Consolidate duplicate agent emoji/name helpers
6. Remove dead AgentCost.percent property
7. Replace DispatchQueue.main.asyncAfter with structured concurrency
8. Remove duplicate network monitoring (use NetworkMonitor.shared)

## Effort Estimate
- **Total: 8-11 days of focused work**
- Sprints 1-3 are the must-haves for production
- Sprint 4 (Calendar) is a feature gap, not a bug
- Sprints 5-6 are quality-of-life
