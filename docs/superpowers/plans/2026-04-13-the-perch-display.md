# The Perch Display Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build The Perch Display, a calm ambient display surface for Meta Portal and other tablet/kiosk hosts that shows what matters now and lets Fábio talk to Claudinho and SideQuest without picking up his phone.

**Architecture:** Treat this as a new surface, not a port of the iOS app. Use a landscape-first web kiosk client in `web/`, powered by one composed display snapshot from Supabase/OpenClaw, plus a voice bridge that routes push-to-talk input to Claudinho and SideQuest and returns text plus spoken replies. Keep business logic in the snapshot/bridge layer and keep the display client dumb, glanceable, and calm.

**Tech Stack:** React + TypeScript + Vite in `web/`, Supabase Edge Functions, existing `skill/dashboard-sync` workers, OpenClaw sessions/messaging, existing ThePerch data sources (calendar, macros, weather, SideQuest signals), optional TTS/STT bridge for voice responses.

---

## Product framing

### What this actually is
This is not “ThePerch on Android.”
It is **The Perch Display**: an ambient home command surface.

Its job is to reduce cognitive load by making the next useful thing visible without asking for attention all day.

### Core product promise
At a glance, Fábio should be able to answer:
- What matters now?
- What is next?
- What needs attention today?
- What should I do or watch out for?
- Can I offload a thought to Claudinho or SideQuest right now?

### Host strategy
**Recommendation:** build a web kiosk client first, with Meta Portal as the first host.

Why this is the right move:
- one surface for Portal, old iPad, cheap Android tablet, browser kiosk, and future standby displays
- lower platform lock-in than a native Android-only build
- faster to iterate on layout than maintaining parallel iOS + Android shells
- lets the product mature before deciding whether a dedicated Android wrapper is worth it

### Product guardrails
- No tabs in v1
- No dense analytics dashboard
- No always-listening microphone
- No chat UI as the main surface
- No generic widget soup

The display earns its place by being calm, ambient, and immediately useful.

---

## Approved v1 direction

### Persistent context rail
Always visible:
- local clock and date
- secondary clocks: SF + Vitória (or chosen Brazil city)
- weather: today + tomorrow

These are not rotating cards. They are the screen’s environmental context.

### Core content blocks
V1 should focus on four blocks only:
1. **Now / Briefing**
   - next event / current focus
   - context note for the next important thing
   - one actionable insight or open loop
   - macros status or SideQuest watchout, whichever is more urgent
2. **Next**
   - next 2-4 meaningful items for the day
   - top Things todos / waiting-fors
3. **Guidance**
   - one synthesized recommendation or steering note for the day
4. **Voice dock**
   - Talk to Claudinho
   - Talk to SideQuest

A conditional **Agent Note** card can appear when there is a fresh reply or proactive note worth surfacing.

### Voice behavior
**Recommendation:** push-to-talk only.

Rules:
- user taps or holds a mic target to speak
- transcript appears instantly
- reply returns as text first, voice when useful
- if the interaction began with voice, spoken reply is the default
- no ambient background listening

### Delivery model
The display should consume **one composed snapshot** instead of separately querying many data sources from the device.

That snapshot should include:
- clocks/timezones
- weather summary
- calendar summary
- briefing context for the next important thing
- macros summary
- Things summary
- SideQuest summary
- guidance text
- fresh agent note preview when relevant

This keeps the device client light and lets the intelligence live in the orchestrator layer.

---

## Recommended architecture

```text
Things / Calendar / Weather / Macros / SideQuest / Telegram / OpenClaw
                │
                ▼
      skill/dashboard-sync + Supabase functions
                │
                ▼
         display snapshot / voice bridge
                │
                ├── web kiosk client (Meta Portal first host)
                └── future native wrappers if ever needed
```

### Why this shape wins
- Portal device stays simple
- integrations stay centralized
- future hosts reuse the same product brain
- voice routing stays tied to OpenClaw, not hardcoded into the display

---

## File structure recommendation

### Planning / product docs
- Create: `docs/plans/the-perch-display-layout-v1.md`
- Create: `docs/plans/the-perch-display-voice-flows-v1.md`
- Create: `docs/plans/the-perch-display-portal-setup.md`
- Modify: `docs/product-brief-v2.md` only if The Perch Display becomes part of the official multi-surface product narrative

### Web display client
- Create: `web/package.json`
- Create: `web/tsconfig.json`
- Create: `web/vite.config.ts`
- Create: `web/index.html`
- Create: `web/src/main.tsx`
- Create: `web/src/App.tsx`
- Create: `web/src/styles/tokens.css`
- Create: `web/src/screens/display/PerchDisplayScreen.tsx`
- Create: `web/src/components/display/HeaderRail.tsx`
- Create: `web/src/components/display/NowCard.tsx`
- Create: `web/src/components/display/NextCard.tsx`
- Create: `web/src/components/display/GuidanceCard.tsx`
- Create: `web/src/components/display/AgentNoteCard.tsx`
- Create: `web/src/components/display/VoiceDock.tsx`
- Create: `web/src/components/display/EmptyDisplayState.tsx`
- Create: `web/src/hooks/useDisplaySnapshot.ts`
- Create: `web/src/hooks/useVoiceSession.ts`
- Create: `web/src/lib/supabase.ts`
- Create: `web/src/lib/formatters.ts`
- Create: `web/src/lib/audio.ts`
- Test: `web/src/screens/display/PerchDisplayScreen.test.tsx`
- Test: `web/src/components/display/VoiceDock.test.tsx`

### Snapshot and orchestration layer
- Create: `supabase/functions/display-snapshot/index.ts`
- Create: `supabase/functions/display-snapshot/display-snapshot.ts`
- Create: `supabase/functions/display-snapshot/display-snapshot.test.ts`
- Create: `supabase/functions/display-voice-bridge/index.ts`
- Create: `supabase/functions/display-voice-bridge/display-voice-bridge.ts`
- Create: `supabase/functions/display-voice-bridge/display-voice-bridge.test.ts`
- Create: `supabase/migrations/<timestamp>_display_snapshot_contract.sql`

### Existing sync/orchestration layer
- Create: `skill/dashboard-sync/src/display-brief.ts`
- Create: `skill/dashboard-sync/src/things-summary.ts`
- Create: `skill/dashboard-sync/src/sidequest-summary.ts`
- Modify: `skill/dashboard-sync/src/index.ts`
- Modify: `skill/dashboard-sync/src/types.ts`
- Test: `skill/dashboard-sync/src/display-brief.test.ts`

### iOS app touchpoints
Only if needed for shared formatting/parity later:
- Modify: `ios/ThePerch/Sources/ThePerch/ViewModels/DashboardViewModel.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Views/Cards/WeatherCompactCard.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Views/Cards/DailySummaryBar.swift`

**Recommendation:** do not start by coupling the Portal surface to iOS view code. Keep the display surface independent.

---

## Technical decisions to lock before implementation

### 1. Snapshot shape
Use one typed display payload, not a bundle of ad hoc records.

Proposed sections:
- `header`: date, local time, secondary clocks, weather today/tomorrow
- `now`: current focus, next event, briefing context, open loop, primary watchout
- `next`: timeline items, todo items, waiting items
- `guidance`: one synthesized sentence or short paragraph
- `agentNote`: fresh reply preview, playback metadata, unread flag, dismissible state

### 2. Things integration
Do **not** try to talk directly to Things from the Portal device.

Instead:
- read Things from the existing Mac/OpenClaw side using the `things` CLI
- summarize to the snapshot/orchestrator layer
- show only the top few actionable items on the display

This keeps the display client stateless and avoids a dead-end device-specific integration.

### 3. Voice bridge
Do not couple voice to Telegram semantics.

Build an abstraction:
- `target = claudinho | sidequest`
- input = text transcript or audio blob
- output = reply text, optional audio URL/blob, latest message metadata

That way the screen talks to product surfaces, not to one specific transport.

### 4. Refresh model
Use:
- periodic snapshot refresh for ambient state
- event-driven refresh on known updates if easy
- explicit refresh after voice interactions

Avoid high-frequency polling.

---

## Execution sequence

**Locked execution order:**
1. freeze layout/spec and voice rules
2. build the web display product surface
3. run it in a desktop browser
4. run it on a normal tablet browser
5. validate the Portal host path on real hardware
6. only then decide whether Portal needs browser-only, a thin Android shell, or launcher-level work

This order is intentional. It protects the product from overfitting to Portal before the surface itself is proven.

## Chunk 1: product spec and layout approval

### Task 1: Freeze the v1 layout and interaction rules before code

**Files:**
- Create: `docs/plans/the-perch-display-layout-v1.md`
- Create: `docs/plans/the-perch-display-voice-flows-v1.md`
- Create: `docs/plans/the-perch-display-portal-setup.md`
- Modify: `docs/superpowers/plans/2026-04-13-the-perch-display.md`

- [ ] **Step 1: Write the layout brief with one landscape-first screen and persistent rails**
- [ ] **Step 2: Write the voice interaction brief with push-to-talk, transcript, and spoken-reply rules**
- [ ] **Step 3: Define the exact v1 module list and explicit non-goals**
- [ ] **Step 4: Review the layout with Fábio and revise until approved**
- [ ] **Step 5: Open/update GitHub issues to match the approved scope**

### Task 2: Freeze the display payload contract

**Files:**
- Create: `docs/plans/the-perch-display-data-contract-v1.md`
- Test: `supabase/functions/display-snapshot/display-snapshot.test.ts`

- [ ] **Step 1: Write the contract doc for the snapshot payload**
- [ ] **Step 2: Write failing tests for required sections and null-handling**
- [ ] **Step 3: Run tests to verify they fail**
- [ ] **Step 4: Keep the contract stable until layout approval is done**
- [ ] **Step 5: Commit docs/tests when approved**

---

## Chunk 2: snapshot engine and source composition

### Task 3: Build the display snapshot function

**Files:**
- Create: `supabase/functions/display-snapshot/index.ts`
- Create: `supabase/functions/display-snapshot/display-snapshot.ts`
- Test: `supabase/functions/display-snapshot/display-snapshot.test.ts`

- [ ] **Step 1: Write failing tests for a complete display snapshot response**
- [ ] **Step 2: Write failing tests for degraded states (missing weather, missing Things, missing SideQuest)**
- [ ] **Step 3: Run tests to verify they fail**
- [ ] **Step 4: Implement the minimal snapshot builder**
- [ ] **Step 5: Run tests to verify they pass**
- [ ] **Step 6: Commit**

### Task 4: Extend dashboard-sync to produce display-ready summaries

**Files:**
- Create: `skill/dashboard-sync/src/display-brief.ts`
- Create: `skill/dashboard-sync/src/things-summary.ts`
- Create: `skill/dashboard-sync/src/sidequest-summary.ts`
- Modify: `skill/dashboard-sync/src/index.ts`
- Modify: `skill/dashboard-sync/src/types.ts`
- Test: `skill/dashboard-sync/src/display-brief.test.ts`

- [ ] **Step 1: Write failing tests for Things summary composition**
- [ ] **Step 2: Write failing tests for SideQuest watchout composition**
- [ ] **Step 3: Run tests to verify they fail**
- [ ] **Step 4: Implement minimal summary builders**
- [ ] **Step 5: Run tests to verify they pass**
- [ ] **Step 6: Commit**

---

## Chunk 3: display runtime shell

### Task 5: Stand up the web kiosk app

**Files:**
- Create: `web/package.json`
- Create: `web/tsconfig.json`
- Create: `web/vite.config.ts`
- Create: `web/index.html`
- Create: `web/src/main.tsx`
- Create: `web/src/App.tsx`
- Test: `web/src/App.test.tsx`

- [ ] **Step 1: Write the failing app-shell smoke test**
- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Create the minimal Vite/React shell**
- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

### Task 6: Build the approved landscape layout

**Files:**
- Create: `web/src/screens/display/PerchDisplayScreen.tsx`
- Create: `web/src/components/display/HeaderRail.tsx`
- Create: `web/src/components/display/NowCard.tsx`
- Create: `web/src/components/display/NextCard.tsx`
- Create: `web/src/components/display/GuidanceCard.tsx`
- Create: `web/src/components/display/AgentNoteCard.tsx`
- Create: `web/src/components/display/VoiceDock.tsx`
- Create: `web/src/styles/tokens.css`
- Test: `web/src/screens/display/PerchDisplayScreen.test.tsx`

- [ ] **Step 1: Write failing render tests for the approved module layout**
- [ ] **Step 2: Run tests to verify they fail**
- [ ] **Step 3: Implement the minimal landscape screen**
- [ ] **Step 4: Run tests to verify they pass**
- [ ] **Step 5: Commit**

### Task 7: Wire the snapshot into the client

**Files:**
- Create: `web/src/hooks/useDisplaySnapshot.ts`
- Create: `web/src/lib/supabase.ts`
- Create: `web/src/lib/formatters.ts`
- Modify: `web/src/screens/display/PerchDisplayScreen.tsx`
- Test: `web/src/hooks/useDisplaySnapshot.test.ts`

- [ ] **Step 1: Write failing tests for loading, success, and degraded snapshot states**
- [ ] **Step 2: Run tests to verify they fail**
- [ ] **Step 3: Implement the snapshot hook and client integration**
- [ ] **Step 4: Run tests to verify they pass**
- [ ] **Step 5: Commit**

---

## Chunk 4: browser validation before Portal-specific work

### Task 8: Validate the web display on desktop and generic tablet hosts

**Files:**
- Create: `docs/plans/the-perch-display-browser-qa.md`
- Modify: `web/index.html`
- Modify: `web/src/styles/tokens.css`
- Test: manual QA checklist in `docs/plans/the-perch-display-browser-qa.md`

- [ ] **Step 1: Write the manual QA checklist for desktop browser validation**
- [ ] **Step 2: Validate readability, reconnect behavior, and ambient idle state on desktop**
- [ ] **Step 3: Validate the same build on a normal tablet browser**
- [ ] **Step 4: Tune spacing, typography, and hit targets based on those tests**
- [ ] **Step 5: Commit**

---

## Chunk 5: Portal host validation spike

### Task 9: Validate the Portal host path before any Android-specific build work

**Files:**
- Create: `docs/plans/the-perch-display-portal-setup.md`
- Test: manual QA checklist in `docs/plans/the-perch-display-portal-setup.md`

- [ ] **Step 1: Verify whether Portal can run the web display reliably in a browser or kiosk-like mode**
- [ ] **Step 2: Validate screen wake/sleep, reconnect, orientation, mic permission, and audio playback on hardware**
- [ ] **Step 3: Validate sideload practicality for a thin WebView shell if browser-only is not enough**
- [ ] **Step 4: Explicitly treat launcher work as last resort and only if the hardware forces it**
- [ ] **Step 5: Record the decision: browser-only vs thin shell vs launcher**
- [ ] **Step 6: Commit**

---

## Chunk 6: voice bridge and spoken replies

### Task 10: Build the backend bridge for Claudinho and SideQuest

**Files:**
- Create: `supabase/functions/display-voice-bridge/index.ts`
- Create: `supabase/functions/display-voice-bridge/display-voice-bridge.ts`
- Test: `supabase/functions/display-voice-bridge/display-voice-bridge.test.ts`

- [ ] **Step 1: Write failing tests for routing to Claudinho and SideQuest**
- [ ] **Step 2: Write failing tests for reply payloads with text plus optional audio metadata**
- [ ] **Step 3: Run tests to verify they fail**
- [ ] **Step 4: Implement the minimal voice bridge**
- [ ] **Step 5: Run tests to verify they pass**
- [ ] **Step 6: Commit**

### Task 11: Build push-to-talk and reply playback in the client

**Files:**
- Create: `web/src/hooks/useVoiceSession.ts`
- Create: `web/src/lib/audio.ts`
- Modify: `web/src/components/display/VoiceDock.tsx`
- Modify: `web/src/components/display/LatestReplyCard.tsx`
- Test: `web/src/components/display/VoiceDock.test.tsx`

- [ ] **Step 1: Write failing tests for talk-state transitions and reply playback**
- [ ] **Step 2: Run tests to verify they fail**
- [ ] **Step 3: Implement the minimal push-to-talk client flow**
- [ ] **Step 4: Run tests to verify they pass**
- [ ] **Step 5: Commit**

## Backlog recommendation

Create one epic with five child issues:
1. layout/spec approval
2. snapshot engine
3. web kiosk runtime
4. Portal host validation spike
5. voice bridge

Do **not** start coding before the layout/spec issue is approved.

---

## CEO recommendation

The winning version is:

**The Perch Display = ambient awareness + instant voice capture**

That means:
- persistent clocks and weather
- a small number of high-signal blocks
- voice as the magic layer
- zero temptation to turn this into a cluttered tablet app

The biggest product mistake would be porting the iPhone UI.
The biggest product win would be making this feel like a calm household surface that quietly keeps the day on the rails.

---

## Success criteria

- Fábio can understand the day in under 3 seconds from across the room
- The screen never feels like a wall of widgets
- Things, SideQuest, macros, calendar, and weather are visible without navigation
- Claudinho and SideQuest can be reached in one tap from the display
- Voice replies feel helpful, not noisy
- The same display client can run on Portal, browser kiosk, or tablet with minimal host-specific work

---

Plan complete and saved to `docs/superpowers/plans/2026-04-13-the-perch-display.md`. Ready to execute?
