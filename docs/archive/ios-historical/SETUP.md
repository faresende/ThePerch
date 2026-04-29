# The Perch iOS App - Quick Start Guide for Fabio

Welcome! This guide will get you up and running with the foundation that's been built for you.

## What's Been Built

A complete **data layer, service layer, and view model layer** with no UI dependencies. You get:

- ✅ Supabase integration (auth, queries, realtime)
- ✅ Local calendar & reminders sync (EventKit)
- ✅ Flexible data model with typed payloads
- ✅ Modern async/await throughout
- ✅ Error handling
- ✅ State management with @Observable

You focus on: **Beautiful UI and intuitive navigation**.

## Getting Started (5 Minutes)

### 1. Open the Project

```bash
cd /sessions/practical-amazing-tesla/mnt/ThePerch/ios/ThePerch
open . # Opens in Finder
# Double-click "ThePerch" to open the Xcode project
# OR use `xed .` to open in Xcode directly
```

Wait, you may need to set this up as an Xcode project. Check if there's an `ThePerch.xcodeproj` file. If not, you can use this as a Swift Package and create a new Xcode project that imports it.

### 2. Create a Secrets.plist

This file holds your Supabase credentials (not committed to git for security).

1. In Xcode, right-click the project navigator
2. Select "Add Files to ThePerch..."
3. Create a new file: `Secrets.plist`
4. Set its contents to:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>SUPABASE_URL</key>
    <string>https://your-project.supabase.co</string>
    <key>SUPABASE_ANON_KEY</key>
    <string>your-anon-key-here</string>
</dict>
</plist>
```

Replace with your actual Supabase credentials.

**Important**: Add `Secrets.plist` to `.gitignore` so it's never committed.

### 3. Verify the Build

```bash
# Build to check for any issues
xcodebuild -scheme ThePerch -configuration Debug
```

If there are errors, check:
- Is `Secrets.plist` created with valid values?
- Do you have the latest version of Xcode (15.0+)?
- Is the iOS deployment target set to 17.0+?

## Architecture Overview (2 Minutes)

Three layers, separated for clarity:

```
Models/          ← Data structures (no UI, no network calls)
  Record, Agent, Section, etc.

Services/        ← Network, file I/O, external APIs
  SupabaseService, EventKitService

ViewModels/      ← State management (@Observable)
  AuthViewModel, DashboardViewModel, SectionViewModel

Views/           ← YOUR DESIGN (does not exist yet)
  LoginView, DashboardView, SectionView, etc.
```

Everything is async/await. No callbacks, no delegates, no RxSwift complexity.

## Key Files to Know

| File | Purpose |
|------|---------|
| `Package.swift` | Dependencies (Supabase Swift SDK) |
| `Models/*.swift` | All data structures |
| `Services/SupabaseService.swift` | Queries, mutations, realtime |
| `Services/EventKitService.swift` | Calendar & reminders |
| `ViewModels/*.swift` | State managers you observe from views |
| `Config/AppConfig.swift` | Config loading (reads Secrets.plist) |
| `ARCHITECTURE.md` | Detailed design docs |

## Common Tasks

### Create a View That Loads Records

```swift
import SwiftUI

struct HealthView: View {
    @State var viewModel = SectionViewModel(category: .health)

    var body: some View {
        List {
            ForEach(viewModel.records) { record in
                VStack(alignment: .leading) {
                    Text(record.title).font(.headline)
                    Text(record.relativeTime).font(.caption)
                }
            }
        }
        .task {
            await viewModel.loadRecords()
        }
    }
}
```

### Access Typed Data from a Record

```swift
// Records have flexible JSON in the `data` field
// But you can decode to strongly-typed structs:

if let measurement = record.asMeasurement() {
    Text("\(measurement.value) \(measurement.unit)")
}

if let delivery = record.asDelivery() {
    Text("Tracking: \(delivery.trackingNumber)")
}

// Types available:
// asMeasurement(), asDelivery(), asEvent(), asStatus(),
// asReminder(), asCostSummary(), asTextNote(), asChecklist()
```

### Sign In/Out

```swift
@State var authVM = AuthViewModel()

// Sign in
authVM.email = "user@example.com"
authVM.password = "password"
await authVM.signIn()

if authVM.error != nil {
    Text(authVM.error?.localizedDescription ?? "Error")
}

// Sign out
await authVM.signOut()
```

### Sort/Filter Records

```swift
let viewModel = SectionViewModel(category: .health)

// Sort
viewModel.setSortOrder(.titleAtoZ)

// Filter by type
let measurements = viewModel.recordsForType(.measurement)

// Search
let results = viewModel.search("blood")

// Pin/unpin
await viewModel.togglePin(recordId: someId)
```

## View Model Environment Setup

In your app, use `@Environment` to pass view models:

```swift
@main
struct ThePerchApp: App {
    @State private var dashboardVM = DashboardViewModel()
    @State private var authVM = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            if authVM.isAuthenticated {
                DashboardView()
                    .environment(dashboardVM)
            } else {
                AuthView()
                    .environment(authVM)
            }
        }
    }
}
```

Then in your views:

```swift
struct DashboardView: View {
    @Environment(DashboardViewModel.self) var viewModel

    var body: some View {
        // Use viewModel
    }
}
```

## Customization Points (Marked with `// TODO: Fabio`)

You'll see these comments in the code where you should customize:

- `ThePerchApp.swift` - Auth/non-auth view switching
- `ContentView.swift` - Main dashboard layout
- `EventKitService.swift` - Which calendars to sync
- View files you create - Everything visual

## Dependencies

**Supabase Swift SDK 2.0.0+**
- Handles auth, queries, realtime subscriptions
- Already declared in `Package.swift`

**EventKit** (built-in)
- macOS/iOS calendar and reminder access

**Observation** (iOS 17+, built-in)
- Modern state management without property wrappers

## Testing Locally

1. Create a test user in your Supabase dashboard
2. Add some test records to the `records` table
3. Sign in and verify data loads

## Next Steps

1. ✅ Create `Secrets.plist` with your Supabase credentials
2. ✅ Build the project to verify setup
3. ✅ Read `ARCHITECTURE.md` for detailed design docs
4. ✅ Start building views:
   - Authentication (login/signup)
   - Dashboard (main view with sections)
   - Section pages (for each category)
   - Record detail pages
5. ✅ Test realtime updates (needs Supabase realtime configured)
6. ✅ Add EventKit syncing (optional, handles calendar/reminders)

## Questions?

Check the comments in the code:
- `// MARK:` sections describe major components
- `// TODO: Fabio` marks places to customize
- Docstring comments explain public interfaces

Good luck! Build something beautiful.
