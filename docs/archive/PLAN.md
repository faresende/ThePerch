# M1 Implementation Plan — ThePerch

**Milestone:** M1 — Make ThePerch shareable (open-sourceable)
**Branch:** `feature/PERCH-M1`
**Issues:** #18, #2, #3, #4, #5
**Date:** 2026-03-18

---

## Issue #18 + #2: Runtime Backend Configuration (Backend-Agnostic)

**Problem:** Supabase URL + anon key are hardcoded in `Secrets.plist` at compile time. Anyone cloning the repo can't run the app. The two-track model (self-hosted vs. ThePerch Cloud) requires runtime configuration.

### Steps

**Step 1: Create `AppConfiguration` model + Keychain service**
- New file: `Sources/ThePerch/Config/AppConfiguration.swift`
  - `struct AppConfiguration`: `supabaseURL: String`, `supabaseAnonKey: String`, `backendMode: BackendMode` (`.selfHosted` / `.managedCloud`)
- New file: `Sources/ThePerch/Services/KeychainService.swift`
  - `func save(_ config: AppConfiguration)`, `func load() -> AppConfiguration?`, `func clear()`
  - Uses `Security` framework (`kSecClassGenericPassword`)

**Step 2: Create first-launch onboarding screen**
- New file: `Sources/ThePerch/Views/Onboarding/OnboardingView.swift`
  - Mode picker: "Self-hosted" / "ThePerch Cloud" (placeholder for now)
  - Self-hosted path: text fields for Supabase URL + anon key, "Connect" button
  - On "Connect": validate URL format, test connection (fetch 1 record), save to Keychain on success
  - Managed cloud path: disabled/"Coming soon" state for now
- New file: `Sources/ThePerch/Views/Onboarding/ConnectionTestView.swift` (spinner + result)

**Step 3: Update `SupabaseService` to read from Keychain**
- Remove all references to `Secrets.plist` in `SupabaseService.swift`
- On init: read `AppConfiguration` from `KeychainService`. If nil → app is unconfigured.
- Add `var isConfigured: Bool` computed property

**Step 4: Update `ThePerchApp.swift` to gate on configuration**
- On launch: check `KeychainService.load()`. If nil → show `OnboardingView`. Otherwise → show `MainTabView`.
- State: `@State private var isConfigured: Bool`

**Step 5: Add "Change Backend" in Settings**
- In `SettingsView` (or wherever settings live): "Backend" section → "Disconnect / Change" → clears Keychain → returns to OnboardingView.

**Step 6: Remove `Secrets.plist` from the project**
- Delete `Secrets.plist`
- Remove from `project.pbxproj`
- Add `Secrets.plist` to `.gitignore` (in case someone adds it back locally)
- Update all remaining references in the codebase (search for `SUPABASE_`)

**Validation criteria:**
- Fresh install shows OnboardingView
- Entering a valid Supabase URL + key → connects → shows MainTabView
- Entering invalid URL → shows error, stays on OnboardingView
- Settings → Change backend → returns to OnboardingView
- `Secrets.plist` no longer exists in repo

---

## Issue #3: Generic SQL Migration Scripts

**Problem:** Self-hosters need to set up the Supabase schema from scratch.

### Steps

**Step 1: Create `backend/` directory in repo root**
- `backend/migrations/001_initial_schema.sql` — creates all tables: `sections`, `dashboard_records`, `users`
- `backend/migrations/002_rls_policies.sql` — Row Level Security policies
- `backend/seed/demo_sections.sql` — seed data for default sections (home, health, workouts, deliveries, etc.)
- `backend/README.md` — how to run the migrations against Supabase

**Validation criteria:**
- A fresh Supabase project can be bootstrapped by running the migrations in order
- The resulting schema matches what the app expects

---

## Issue #4: README + Setup Guide

**Problem:** No documentation for self-hosters.

### Steps

**Step 1: Rewrite root `README.md`**
- What is ThePerch (1 paragraph)
- Prerequisites: Xcode, Swift, Supabase account
- Setup: clone → run migrations → open app → enter Supabase URL/key
- Architecture overview (brief)
- Contributing section
- License

**Validation criteria:**
- A developer with zero prior knowledge can set up a running instance by following the README

---

## Issue #5: Open-Source Repo Cleanup

**Problem:** Repo may contain personal data, hardcoded credentials, or sensitive history.

### Steps

**Step 1: Audit what's in the repo**
- Run `git log --all -- Secrets.plist` to check if it was ever committed
- Run `grep -r "supabase.co\|eyJ" ios/` to find hardcoded keys
- Check for any personal data (names, addresses, NIF, passport numbers) in code/comments/tests

**Step 2: Clean sensitive history if needed**
- If `Secrets.plist` was committed: use `git filter-repo` or BFG to remove it from history
- If hardcoded keys found: rotate the Supabase anon key, then remove from code

**Step 3: `.gitignore` audit**
- Ensure `Secrets.plist`, `*.p8`, `*.p12`, `AuthKey_*` are in `.gitignore`
- Ensure derived data and xcuserstate are ignored

**Validation criteria:**
- `git log --all -S "supabase.co"` returns no results with actual keys
- `Secrets.plist` not in repo history (or if it is, key has been rotated)
- `.gitignore` covers all secret file patterns

---

## Execution Order

```
1. Issue #5 (audit)          — non-destructive, informs everything else
2. Issue #18/#2 (runtime config) — biggest code change, must be done on branch
3. Issue #3 (SQL migrations)  — independent, no code dependencies
4. Issue #4 (README)          — written last when config UX is settled
5. Issue #5 (cleanup/history) — finalize after keys are confirmed removed
```

---

## Files Affected

```
NEW:
  ios/ThePerch/Sources/ThePerch/Config/AppConfiguration.swift
  ios/ThePerch/Sources/ThePerch/Services/KeychainService.swift
  ios/ThePerch/Views/Onboarding/OnboardingView.swift
  ios/ThePerch/Views/Onboarding/ConnectionTestView.swift
  backend/migrations/001_initial_schema.sql
  backend/migrations/002_rls_policies.sql
  backend/seed/demo_sections.sql
  backend/README.md

MODIFIED:
  ios/ThePerch/Sources/ThePerch/Services/SupabaseService.swift
  ios/ThePerch/Sources/ThePerch/ThePerchApp.swift
  ios/ThePerch/ThePerch.xcodeproj/project.pbxproj
  README.md
  .gitignore

DELETED:
  ios/ThePerch/Sources/ThePerch/Config/Secrets.plist
```
