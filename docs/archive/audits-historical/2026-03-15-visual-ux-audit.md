# ThePerch Visual/UX Production Readiness Audit
**Date:** 2026-03-15
**Auditor:** Bancada

## Summary

| Tab | Critical | Warning | Polish | Total |
|-----|----------|---------|--------|-------|
| Home | 4 | 9 | 6 | 19 |
| Health | 2 | 6 | 6 | 14 |
| Deliveries | 1 | 5 | 5 | 11 |
| Travel | 0 | 2 | 3 | 5 |
| Calendar | 2 | 4 | 3 | 9 |
| Admin | 3 | 7 | 6 | 16 |
| Global | 1 | 1 | 0 | 2 |
| **TOTAL** | **13** | **34** | **29** | **76** |

## Top 10 Critical Issues (Ship Blockers)

1. **Macro bar colors inconsistent** between Home and Health tabs (different colors for same nutrients)
2. **No empty states** for any screen (new users see blank pages)
3. **No loading states** (no skeletons/shimmers while data loads)
4. **Calendar has no date navigation** (only shows today, can't browse)
5. **Calendar is basically a stub** (no week/month view, huge empty space)
6. **"cancelled" error banner** is vague, no dismiss button, appears on every tab
7. **Inconsistent accent colors** (amber, teal, blue used without semantic meaning)
8. **Remote admin actions have no confirmation dialog** (restart gateway = one tap)
9. **OpenClaw "Unknown" status has no resolution action**
10. **Event titles truncate** despite having space to wrap

## Priorities for Production Pass

### P0: Ship blockers (must fix)
- Consistent macro colors across all screens
- Empty states for every tab/section
- Loading states (skeleton screens)
- Error banner redesign (clear message, dismiss, auto-retry)
- Calendar date navigation (at minimum day-by-day)
- Confirmation dialogs for admin actions

### P1: Quality issues (should fix)
- Consistent accent color system (define when to use amber vs other colors)
- Card interaction affordances (tap hints, chevrons)
- Stale data warnings (consistent "Updated X ago" + thresholds)
- Tab bar truncation fix
- Event title wrapping
- Agent card descriptions
- Consistent typography weights across card titles

### P2: Polish (nice to fix)
- Pull-to-refresh discovery
- Greeting compactness
- Card border consistency
- Timezone display for international events
- Weight chart prominence
- Progress tracker animations
- Grouped confirmation numbers (already done for travel)
