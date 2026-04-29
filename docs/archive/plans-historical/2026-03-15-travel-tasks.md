# Travel Tasks Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add trip-linked to-do lists to the Travel tab, with pre-trip checklist and day-linked tasks that show inline in the timeline.

**Architecture:** New `travel_task` record type in Supabase, rendered as a checklist card above the timeline (pre-trip) and inline task entries within timeline days (day-linked). Toggle done state via existing `updateRecordData` pattern (same as MedicationsCard).

**Tech Stack:** Swift/SwiftUI, Supabase REST API, existing SupabaseService

---

## File Structure

- **Create:** `Sources/ThePerch/Models/DataPayloads.swift` -- add `TravelTaskData` struct (append to existing file)
- **Modify:** `Sources/ThePerch/Models/Record.swift` -- add `travelTask` case to `RecordType` enum
- **Modify:** `Sources/ThePerch/ViewModels/TravelViewModel.swift` -- add task helpers
- **Modify:** `Sources/ThePerch/ViewModels/DashboardViewModel.swift` -- add travel_task to travel category
- **Create:** `Sources/ThePerch/Views/Cards/TravelTasksCard.swift` -- pre-trip checklist card
- **Modify:** `Sources/ThePerch/Views/Sections/TravelView.swift` -- integrate tasks card + inline timeline tasks
- **Add to pbxproj:** TravelTasksCard.swift

---

### Task 1: Data Model

**Files:**
- Modify: `Sources/ThePerch/Models/Record.swift`
- Modify: `Sources/ThePerch/Models/DataPayloads.swift`

- [ ] **Step 1: Add RecordType case**

In Record.swift, add to RecordType enum:
```swift
case travelTask = "travel_task"
```

Add display hint and category mapping.

- [ ] **Step 2: Add TravelTaskData struct**

In DataPayloads.swift, add:
```swift
struct TravelTaskData: Codable {
    let tripId: String
    let task: String
    let date: String?          // yyyy-MM-dd, nil = pre-trip
    let phase: String?         // "before" or "during", inferred from date if nil
    let done: Bool

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case task, date, phase, done
    }

    var isPretripTask: Bool {
        date == nil || phase == "before"
    }

    var dateParsed: Date? {
        guard let date else { return nil }
        return PerchFormatters.isoDate.date(from: date)
    }
}
```

Add `asTravelTask()` extension on Record.

- [ ] **Step 3: Commit**
```bash
git commit -m "feat: add TravelTaskData model and record type"
```

### Task 2: ViewModel Support

**Files:**
- Modify: `Sources/ThePerch/ViewModels/TravelViewModel.swift`
- Modify: `Sources/ThePerch/ViewModels/DashboardViewModel.swift`

- [ ] **Step 1: Add task helpers to TravelViewModel**

```swift
// Pre-trip tasks (no date or phase == "before")
func preTripTasks(for tripId: String) -> [(Record, TravelTaskData)] {
    records.compactMap { record -> (Record, TravelTaskData)? in
        guard let task = record.asTravelTask(), task.tripId == tripId, task.isPretripTask else { return nil }
        return (record, task)
    }.sorted { ($0.1.done ? 1 : 0) < ($1.1.done ? 1 : 0) }
}

// Day-linked tasks for a specific date
func dayTasks(for tripId: String, on date: String) -> [(Record, TravelTaskData)] {
    records.compactMap { record -> (Record, TravelTaskData)? in
        guard let task = record.asTravelTask(), task.tripId == tripId, task.date == date else { return nil }
        return (record, task)
    }.sorted { ($0.1.done ? 1 : 0) < ($1.1.done ? 1 : 0) }
}

// All tasks for a trip
func allTasks(for tripId: String) -> [(Record, TravelTaskData)] {
    records.compactMap { record -> (Record, TravelTaskData)? in
        guard let task = record.asTravelTask(), task.tripId == tripId else { return nil }
        return (record, task)
    }
}
```

- [ ] **Step 2: Add travel_task to DashboardViewModel category routing**

In the switch on record type in DashboardViewModel, add `case .travelTask:` under `.travel` category.

- [ ] **Step 3: Commit**
```bash
git commit -m "feat: add travel task helpers to TravelViewModel"
```

### Task 3: Pre-trip Checklist Card

**Files:**
- Create: `Sources/ThePerch/Views/Cards/TravelTasksCard.swift`
- Add to: `ThePerch.xcodeproj/project.pbxproj`

- [ ] **Step 1: Build TravelTasksCard**

Pattern from MedicationsCard: checklist with toggleable items, haptic feedback, optimistic Supabase update.

Card layout:
- Section header "TRIP PREP" with count badge (3/7)
- Checklist items with checkboxes
- Checked items: strikethrough + muted
- Unchecked items: primary text
- Tap to toggle done state

- [ ] **Step 2: Add file to pbxproj**

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**
```bash
git commit -m "feat: add TravelTasksCard with toggle support"
```

### Task 4: Integrate into TravelView

**Files:**
- Modify: `Sources/ThePerch/Views/Sections/TravelView.swift`

- [ ] **Step 1: Add pre-trip checklist card**

Show above the itinerary timeline when there are pre-trip tasks:
```swift
let preTripTasks = viewModel.preTripTasks(for: trip.tripId)
if !preTripTasks.isEmpty {
    TravelTasksCard(tasks: preTripTasks)
        .cardAppear(index: 1, appeared: cardsAppeared)
        .padding(.horizontal, PerchTheme.Spacing.large)
}
```

- [ ] **Step 2: Add inline day tasks to timeline**

In `itineraryTimeline`, after rendering segments for a day, render any tasks for that date as compact checklist items within the timeline.

- [ ] **Step 3: Build, run on simulator, screenshot**

- [ ] **Step 4: Commit**
```bash
git commit -m "feat: integrate travel tasks into TravelView"
```

### Task 5: Update Claudinho's docs

- [ ] **Step 1: Update reference/infrastructure.md**

Add `travel_task` to the travel records documentation with the JSON schema.

- [ ] **Step 2: Tell Claudinho to push existing trip tasks to Supabase**

- [ ] **Step 3: Commit**
```bash
git commit -m "docs: add travel_task schema to infrastructure reference"
```
