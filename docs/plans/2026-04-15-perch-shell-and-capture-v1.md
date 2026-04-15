# The Perch Shell + Capture V1 Implementation Plan

> For Hermes: Use subagent-driven-development skill to implement this plan task-by-task. Use Codex or Claude Code for implementation, but Hermes owns review, verification, and the release verdict.

Goal: Ship a clearer The Perch shell built around Today, Health, Hub, and one universal capture action, while preserving Wife Mode correctness work and avoiding product drift.

Architecture: Keep a native iOS bottom TabView as the root shell and use custom in-tab subnavigation only where needed, namely Health and Hub. Treat the floating plus button as a capture router, not a generic create action, and require user confirmation before any write. Keep the root shell mostly stable across users in v1, and personalize via per-user defaults, visible segments, and content, not by fragmenting the app into different root structures.

Tech Stack: SwiftUI, native TabView APIs including tabBarMinimizeBehavior where supported, existing DashboardViewModel single-fetch architecture, existing NutritionService and nutrition-copilot edge function, new capture-routing edge function for multi-intent ingestion, iOS simulator build and launch verification.

---

## Locked product decisions

These are the decisions this plan assumes and should not re-open during implementation:

1. Root navigation is Today, Health, Hub, plus one floating capture button.
2. Settings leaves the bottom tab bar.
3. Today has no secondary subnav.
4. Health uses Overview, Workouts, Nutrition.
5. Sleep stays inside Health Overview for v1.
6. Hub uses Deliveries, Saved, Calendar, Travel.
7. Root shell stays mostly stable across users in v1.
8. Avatar/profile access is Today-prominent, but still globally reachable.
9. The plus button means capture anything.
10. AI may classify, but user confirms before writes.
11. v1 capture supports camera and library. Multi-image is allowed only if it comes cheaply and stays capped.
12. Wife Mode correctness lands before broader shell redesign is considered complete.

---

## Current repo and sequencing guardrail

Current app trunk for iOS work:
- `/Users/faresende/Documents/Apps/ThePerch`

Current Wife Mode correctness work in progress:
- worktree: `/Users/faresende/Documents/Apps/ThePerch-wife-slice-a`
- branch: `wife-slice-a-phase1`

Important sequencing rule:
- Do not start broad shell redesign on top of an unmerged Wife Mode patch.
- First, review and land the Wife Mode Slice A correctness work into trunk or an approved integration branch.
- Then build the new shell on top of that corrected user/session foundation.

---

## Success criteria

A successful V1 shell and capture rollout means:

- The app opens into Today by default.
- Root nav is Today, Health, Hub only.
- The native bottom tab bar minimizes correctly on supported iPhone scroll behavior.
- The tab bar material and translucency are materially closer to Apple Music than the current implementation.
- Health subnav is one tap and legible in both selected and non-selected states.
- Hub subnav is one tap and legible in both selected and non-selected states.
- Avatar/profile entry is obvious on Today and reachable everywhere.
- The plus button opens a half-sheet capture flow.
- Camera and photo library both work.
- AI classification is followed by explicit user confirmation.
- Meal capture can route end to end.
- Workout sheet capture can route end to end.
- No write occurs under a fake or default user.
- Build succeeds, simulator launch succeeds, and the changed surfaces are visually checked.

---

## Phase 0: Land Wife Mode Slice A and lock the execution baseline

### Task 0.1: Review and land Wife Mode correctness patch

Objective: Make second-user correctness the floor before UI expansion.

Files:
- Review existing changes in `/Users/faresende/Documents/Apps/ThePerch-wife-slice-a`
- Land to `/Users/faresende/Documents/Apps/ThePerch`

Step 1: Review the current diff and preserve only the intended Slice A files.

Files expected:
- `ios/ThePerch/Sources/ThePerch/Services/SupabaseService.swift`
- `ios/ThePerch/Sources/ThePerch/ViewModels/DashboardViewModel.swift`
- `ios/ThePerch/Sources/ThePerch/Services/BackgroundRefreshService.swift`
- `ios/ThePerch/Sources/ThePerch/Services/HealthKitSyncService.swift`
- `ios/ThePerch/Sources/ThePerch/Services/AdminCommandService.swift`
- `ios/ThePerch/Sources/ThePerch/ViewModels/NutritionViewModel.swift`
- `ios/ThePerch/Sources/ThePerch/Views/App/HealthTab.swift`
- `ios/ThePerch/Sources/ThePerch/Views/Sections/NutritionView.swift`

Step 2: Build and launch again from the target branch.

Run:
- `xcodebuild -project ios/ThePerch/ThePerch.xcodeproj -scheme ThePerch -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- `xcrun simctl install <device-id> <app-path>`
- `xcrun simctl launch <device-id> NotButter.ThePerch`

Expected:
- Build succeeds
- App launches to auth or restored session flow

Step 3: Commit with a narrow message.

Suggested commit:
- `fix: isolate user-scoped cache and write paths for wife slice A`

Exit criteria:
- currentUserId exists as a real session-derived source of truth
- dangerous default-user write fallbacks are fenced on touched paths
- launch still works

### Task 0.2: Create shell-integration branch from corrected trunk

Objective: Ensure shell redesign does not fork away from correctness work.

Files:
- no code changes

Step 1: Branch from the corrected trunk after Task 0.1.

Suggested branch name:
- `shell-capture-v1`

Exit criteria:
- There is one clear branch to build the new shell on top of

---

## Phase 1: Root shell refactor, Today / Health / Hub + floating capture

### Task 1.1: Remove Settings from root tab bar and add shell state model

Objective: Make the root shell match the new product model.

Files:
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/MainTabView.swift`
- Create: `ios/ThePerch/Sources/ThePerch/Views/App/CaptureFab.swift`
- Create: `ios/ThePerch/Sources/ThePerch/Views/App/ProfileEntryButton.swift`

Step 1: Reduce root tabs from 4 to 3.

New root tabs:
- Today
- Health
- Hub

Step 2: Add floating capture button overlay anchored near the tab bar.

Step 3: Add shell-level state for presenting the capture half-sheet.

Step 4: Add shell-level state for presenting settings/profile flow.

Verification:
- App builds
- Tab bar shows only Today, Health, Hub
- Floating plus appears above or adjacent to the bar without clipping

### Task 1.2: Adopt native tab bar minimization behavior

Objective: Stop faking native tab behavior and let the system do the work.

Files:
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/MainTabView.swift`

Step 1: Use the native SwiftUI tab bar minimization behavior on supported iPhone contexts.

Expected API direction:
- `tabBarMinimizeBehavior(.onScrollDown)` or the most appropriate native behavior after testing

Step 2: Verify this is only applied where the behavior is actually supported.

Verification:
- Scroll in Today, Health, and Hub on iPhone simulator
- Tab bar minimizes in a system-native way instead of custom hacks

### Task 1.3: Tune tab bar material and selection styling

Objective: Move the bar materially closer to Apple Music quality without over-customizing it.

Files:
- Modify: `ios/ThePerch/Sources/ThePerch/Views/Theme/PerchTheme.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/MainTabView.swift`

Step 1: Adjust accent treatment so the selected root section uses Perch colors in a polished way.

Step 2: Improve translucency and chrome material treatment without replacing native behavior.

Step 3: Verify readability in dark and light mode.

Verification:
- screenshots in dark and light mode
- no muddy text contrast
- no heavy opaque look

---

## Phase 2: Profile and settings access redesign

### Task 2.1: Move settings entry to avatar/profile access

Objective: Make settings feel like an affordance, not a destination.

Files:
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/TodayTab.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/HealthTab.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/HubTab.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/SettingsTab.swift`
- Create: `ios/ThePerch/Sources/ThePerch/Views/App/ProfileEntryButton.swift` if not already created in Phase 1

Step 1: Add a prominent avatar/profile affordance in Today top-right.

Step 2: Keep profile/settings globally reachable in Health and Hub via the same toolbar slot, but visually less dominant than in Today.

Step 3: Present SettingsTab through navigation or a sheet route from that entry point.

Verification:
- Today shows avatar/profile action clearly
- Health and Hub can still reach settings without returning to Today

---

## Phase 3: Health and Hub subnav redesign

### Task 3.1: Replace generic segmented-control presentation with Apple-Mail-style subtab strip

Objective: Match the new sketch and support selected label plus unselected icon behavior.

Files:
- Create: `ios/ThePerch/Sources/ThePerch/Views/App/SecondaryTabStrip.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/HealthTab.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/HubTab.swift`

Step 1: Build a reusable subtab strip component with:
- selected state: icon + label + filled pill styling
- non-selected state: icon-only pill or compressed presentation
- horizontal scrolling if truly needed, but avoid overflow if possible

Step 2: Use it in HealthTab.

Health labels:
- Overview
- Workouts
- Nutrition

Step 3: Use it in HubTab.

Hub labels:
- Deliveries
- Saved
- Calendar
- Travel

Step 4: Rename internal Hub segments where appropriate.
- `orders` user-facing label becomes Deliveries
- `bookmarks` user-facing label becomes Saved

Verification:
- selected and non-selected states are obvious
- icon-only collapsed state remains legible
- no truncation or clipping in common iPhone sizes

### Task 3.2: Keep Today free of secondary nav

Objective: Make Today feel like a dashboard, not a folder.

Files:
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/TodayTab.swift`

Step 1: Do not add a subtab strip to Today.

Step 2: Make the top-right avatar and the content hierarchy carry the screen identity.

Verification:
- Today reads as a single coherent dashboard
- no redundant navigation chrome appears above the content

---

## Phase 4: Universal capture flow, V1 shell

### Task 4.1: Generalize MealInputSheet into a capture sheet architecture

Objective: Stop thinking in “meal-only input” terms and build the shell for capture-anything.

Files:
- Create: `ios/ThePerch/Sources/ThePerch/Models/CaptureIntent.swift`
- Create: `ios/ThePerch/Sources/ThePerch/Models/CaptureDraft.swift`
- Create: `ios/ThePerch/Sources/ThePerch/Views/App/CaptureSheet.swift`
- Create: `ios/ThePerch/Sources/ThePerch/Views/App/CaptureReviewSheet.swift`
- Keep or adapt: `ios/ThePerch/Sources/ThePerch/Views/Cards/MealInputSheet.swift`

Step 1: Introduce a capture draft model that can hold:
- free text
- one or more images
- source, camera or library
- proposed intent
- confirmed intent

Step 2: Present the root capture flow as a half sheet from the plus button.

Step 3: Support:
- camera capture
- photo library selection
- text input

Step 4: If multi-image is adopted in v1, cap it deliberately.

Suggested cap:
- up to 3 images

Verification:
- capture sheet opens from anywhere in the app shell
- camera and library paths both function
- dismissal behavior is clean

### Task 4.2: Build capture classification and confirmation flow

Objective: Let AI route, but keep the user in control.

Files:
- Create: `ios/ThePerch/Sources/ThePerch/Services/CaptureRouterService.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/CaptureSheet.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/CaptureReviewSheet.swift`

Step 1: Add a route classification step that proposes an intent:
- meal
- workout
- unsupported or review needed

Step 2: Show the proposed type and require the user to confirm or change it.

Step 3: Only after confirmation, continue to review and final submit.

Verification:
- misclassification does not silently write the wrong thing
- users can override type before commit

---

## Phase 5: Capture backend, V1 routes

### Task 5.1: Create a capture-anything edge function shell

Objective: Add a single backend intake surface that can classify and route to current domain handlers.

Files:
- Create: `supabase/functions/capture-anything/index.ts`
- Create: `supabase/functions/capture-anything/classify.ts`
- Create: `supabase/functions/capture-anything/routes/nutrition.ts`
- Create: `supabase/functions/capture-anything/routes/workout.ts`
- Create: `supabase/functions/capture-anything/capture-anything.test.ts`

Step 1: Accept text, image, or images plus user_id.

Step 2: Return a proposed intent and parsed preview payload.

Step 3: Route meal submissions to the existing nutrition infrastructure where possible.

Step 4: Create a minimal workout ingestion route for workout sheet parsing.

Important scope rule:
- Do not add travel/ticket/trip parsing in v1.

Verification:
- request tests pass for classification and parse shape
- errors are explicit and user-safe

### Task 5.2: Wire nutrition capture to the existing nutrition-copilot path

Objective: Reuse what already works.

Files:
- Modify: `ios/ThePerch/Sources/ThePerch/Services/NutritionService.swift`
- Inspect and reuse: `supabase/functions/nutrition-copilot/index.ts`
- Inspect and reuse: `supabase/functions/nutrition-copilot/nutrition-service.ts`

Step 1: Keep meal capture routing through existing nutrition paths when the intent is meal.

Step 2: Preserve user_id correctness from Wife Mode work.

Verification:
- captured meal flow still lands in nutrition records correctly

### Task 5.3: Add first workout-sheet ingestion route

Objective: Make the plus button valuable beyond meals.

Files:
- Create: `ios/ThePerch/Sources/ThePerch/Services/WorkoutCaptureService.swift`
- Create or modify parser/backend files under `supabase/functions/capture-anything/routes/workout.ts`
- Modify: `ios/ThePerch/Sources/ThePerch/Models/DataPayloads.swift` only if new payload support is required

Step 1: Parse a photographed workout sheet into a reviewable draft.

Step 2: Let user confirm before logging.

Step 3: Write the workout to the correct user_id.

Verification:
- at least one representative workout capture can be reviewed and logged end to end

---

## Phase 6: User-specific defaults without root-shell fragmentation

### Task 6.1: Add per-user shell configuration for defaults, not root shell explosion

Objective: Personalize cleanly without turning the app into a different product per user.

Files:
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/MainTabView.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/HealthTab.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/HubTab.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/SettingsTab.swift`
- Reuse or extend existing user/profile preference sources

Step 1: Keep Today, Health, Hub as the v1 root shell.

Step 2: Allow per-user defaults such as:
- default Health subtab
- visible Hub subpages
- whether Travel appears
- future profile photo/settings details

Step 3: Do not remove Hub entirely for one user in v1 unless real usage later justifies it.

Verification:
- user defaults change the experience without breaking the shared mental model

---

## File map summary

### Core files to modify
- `ios/ThePerch/Sources/ThePerch/Views/App/MainTabView.swift`
- `ios/ThePerch/Sources/ThePerch/Views/App/TodayTab.swift`
- `ios/ThePerch/Sources/ThePerch/Views/App/HealthTab.swift`
- `ios/ThePerch/Sources/ThePerch/Views/App/HubTab.swift`
- `ios/ThePerch/Sources/ThePerch/Views/App/SettingsTab.swift`
- `ios/ThePerch/Sources/ThePerch/Views/Theme/PerchTheme.swift`
- `ios/ThePerch/Sources/ThePerch/Views/Cards/MealInputSheet.swift`
- `ios/ThePerch/Sources/ThePerch/Services/NutritionService.swift`

### New iOS files likely needed
- `ios/ThePerch/Sources/ThePerch/Views/App/CaptureFab.swift`
- `ios/ThePerch/Sources/ThePerch/Views/App/CaptureSheet.swift`
- `ios/ThePerch/Sources/ThePerch/Views/App/CaptureReviewSheet.swift`
- `ios/ThePerch/Sources/ThePerch/Views/App/ProfileEntryButton.swift`
- `ios/ThePerch/Sources/ThePerch/Views/App/SecondaryTabStrip.swift`
- `ios/ThePerch/Sources/ThePerch/Models/CaptureIntent.swift`
- `ios/ThePerch/Sources/ThePerch/Models/CaptureDraft.swift`
- `ios/ThePerch/Sources/ThePerch/Services/CaptureRouterService.swift`
- `ios/ThePerch/Sources/ThePerch/Services/WorkoutCaptureService.swift`

### New backend files likely needed
- `supabase/functions/capture-anything/index.ts`
- `supabase/functions/capture-anything/classify.ts`
- `supabase/functions/capture-anything/routes/nutrition.ts`
- `supabase/functions/capture-anything/routes/workout.ts`
- `supabase/functions/capture-anything/capture-anything.test.ts`

---

## Verification plan

For each meaningful phase:

Build:
- `xcodebuild -project ios/ThePerch/ThePerch.xcodeproj -scheme ThePerch -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`

Runtime smoke:
- `xcrun simctl boot <device-id>`
- `xcrun simctl install <device-id> <app-path>`
- `xcrun simctl launch <device-id> NotButter.ThePerch`

Visual QA:
- capture simulator screenshots for:
  - Today root shell
  - Health subnav
  - Hub subnav
  - profile/settings entry
  - capture sheet
  - capture review sheet

Backend verification:
- run edge function tests for capture-anything and nutrition-copilot

User-flow verification before any beta claim:
- meal capture from camera
- meal capture from library
- workout-sheet capture from image
- signed-out fences for write paths
- user A versus user B isolation remains intact

---

## Recommended implementation order

1. Land Wife Mode Slice A into trunk.
2. Build the new 3-tab root shell and remove Settings from root nav.
3. Add avatar/profile entry and keep it globally reachable.
4. Replace Health and Hub secondary navigation with the new subtab strip.
5. Add the floating capture button and empty shell.
6. Generalize capture drafts and review flow.
7. Route meals through the new capture shell.
8. Add workout-sheet routing.
9. Add per-user defaults only after the shell and capture behavior are stable.

---

## Release recommendation for this workstream

This is not one release. It is a sequence.

Recommended release slicing:
- Slice 1: Wife Mode correctness, alpha
- Slice 2: 3-tab shell plus avatar/settings move, alpha
- Slice 3: Health and Hub subtab redesign, alpha
- Slice 4: capture-anything meal flow, alpha
- Slice 5: workout-sheet capture, alpha
- Beta only after live-flow verification across real users and real capture behavior

---

## Bottom line

The shell should become:
- Today for context
- Health for body management
- Hub for operational life surfaces
- one universal capture action to ingest reality into the system

The product risk to avoid is over-personalized shell fragmentation.
The product opportunity to pursue is a capture flow that makes The Perch feel more useful every time the user sees something in the world and knows the app can absorb it.
