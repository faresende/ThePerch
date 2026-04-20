# M2 Implementation Plan — ThePerch

**Milestone:** M2 — Make ThePerch configurable (multi-user ready)
**Branch:** `feature/PERCH-M2`
**Issues:** #7 (Settings), #8 (Onboarding flow), #9 (Agent integration guide)
**Date:** 2026-03-18
**Skipping:** #6 (Dynamic RecordCategory enum) — requires separate arch review

---

## Issue #7: Settings Screen — Show/Hide/Reorder Tabs

**Current state:** No settings screen exists beyond a stub. Users can't control which tabs appear.

### Steps

**Step 1: Create SettingsView tab management section**
- File: `Sources/ThePerch/Views/Settings/SettingsView.swift` (may already exist — check)
- Add a "Tabs" section showing all sections from `dashboardViewModel.sections`
- Each row: toggle for `isVisible`, drag handle for `sortOrder`
- Use `List` with `.onMove` for reordering
- On change: call `dashboardViewModel.reorderSections()` / `toggleSectionVisibility()`

**Step 2: Wire settings to MainTabView**
- Settings button already in HomeView header — verify it opens SettingsView
- After save: `visibleSections` computed property in MainTabView automatically updates

**Validation:**
- Toggle a tab off → it disappears from the pill bar
- Reorder tabs → pill bar reorders on dismiss
- Change persists on app relaunch (saved to Supabase `sections` table)

---

## Issue #8: Onboarding Flow Polish

**Current state:** OnboardingView exists but is sparse. Need to make it feel like a real first-run experience.

### Steps

**Step 1: Add "Change backend" to SettingsView**
- Settings → "Backend" section → shows current mode (Self-hosted / Cloud)
- "Change backend" button → clears Keychain → navigates to OnboardingView
- Use `@Environment(\.dismiss)` pattern or app-level state

**Step 2: OnboardingView polish**
- Add ThePerch logo/wordmark at top
- Better empty-state copy for the managed cloud option
- Keyboard handling: "Done" on URL field moves focus to key field, "Connect" on key field triggers connection
- Add a "How do I find these?" help link that shows a sheet explaining Supabase project URL + anon key

**Validation:**
- Settings → Change backend → shows OnboardingView
- Keyboard flow works smoothly
- Help sheet explains where to find credentials

---

## Issue #9: Agent Integration Guide (Docs)

**Current state:** No documentation on how to connect agents (BioChecha, Claudinho, etc.) to a self-hosted instance.

### Steps

**Step 1: Create `docs/agent-integration.md`**

Cover:
- What agents are and how they write to `dashboard_records`
- Required fields in a `dashboard_records` INSERT (user_id, agent_id, type, category, title, data, display_hint)
- Supported `type` values and their `data` schemas (measurement, delivery, workout_session, etc.)
- Authentication: agents should use the `service_role` key, not the `anon` key
- Example: Python snippet showing a minimal agent writing a measurement record
- Example: curl snippet for quick testing

**Step 2: Update root README.md**
- Add "Connecting Agents" section that links to `docs/agent-integration.md`

---

## Execution Order

```
1. Issue #7 (Settings tab management)   — most user-visible
2. Issue #8 (Onboarding polish)         — completes M1 properly
3. Issue #9 (Agent docs)               — pure docs, independent
```

---

## Files Affected

```
MODIFIED:
  ios/ThePerch/Sources/ThePerch/Views/Settings/SettingsView.swift
  ios/ThePerch/Sources/ThePerch/Views/Sections/OnboardingView.swift
  README.md

NEW:
  docs/agent-integration.md
```
