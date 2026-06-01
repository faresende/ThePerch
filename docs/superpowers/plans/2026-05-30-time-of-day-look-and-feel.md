# Time-of-Day Look-and-Feel Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring The Perch's UI into alignment with the locked `handoff_time_of_day` design — a continuous four-moment time-of-day arc (morning→afternoon→evening→night) with real bundled fonts, the single-marker highlight, an editorial header strip, and tightened density — applied **app-wide** so every tab re-tints with the hour and night goes truly dark.

**Architecture:** The app already has a time-of-day system (`PerchPalette` + `PerchTimeOfDay`, environment-injected at `MainTabView`). This pass (a) revises the four palettes to the locked handoff hex values (incl. the dark-indigo night and the removal of bright-hour lavender), (b) bundles the four type families via Asset Catalog Data Sets + CTFontManager runtime registration (no `.pbxproj`/Info.plist edits), (c) adds a reusable `.perchMark` highlight applied only on the Biochecha working phrase (data-driven via a new `marked_phrase` field), (d) restructures the hero into a 188pt scroll-over strip that keeps the looping video, and (e) propagates the palette to the remaining tabs via a fixed migration recipe. Logic that is unit-testable (schedule boundaries, marker range-finding, `marked_phrase` decoding) gets Swift Testing tests; visual changes are verified by building + running the simulator at each of the four times.

**Tech Stack:** SwiftUI + Observation (`@Observable`), Xcode project (`ThePerch.xcodeproj`, `GENERATE_INFOPLIST_FILE = YES`), Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`), Supabase Swift SDK, a Python LLM insight agent (`agents/health-integrations/biochecha_dynamic_insight.py`), CoreText (`CTFontManagerRegisterGraphicsFont`).

---

## Conventions for this plan

- **Repo root:** `/Users/faresende/Developer/ThePerch`. All paths below are relative to it.
- **Build command (compile check):**
  ```bash
  xcodebuild -project ios/ThePerch/ThePerch.xcodeproj -scheme ThePerch \
    -configuration Debug -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -30
  ```
- **Test command:**
  ```bash
  xcodebuild test -project ios/ThePerch/ThePerch.xcodeproj -scheme ThePerch \
    -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -40
  ```
- **Visual verification (per the look-and-feel goal):** boot a simulator, install, launch, and screenshot. Force a given time-of-day with the debug override added in Task 2.5 (env var `PERCH_TOD_OVERRIDE=morning|afternoon|evening|night`) so all four can be checked without waiting for the wall clock:
  ```bash
  xcrun simctl boot "iPhone 16" 2>/dev/null; open -a Simulator
  # build+install via xcodebuild, then:
  PERCH_TOD_OVERRIDE=night xcrun simctl launch --console "iPhone 16" com.<bundleid>.ThePerch
  xcrun simctl io "iPhone 16" screenshot /tmp/perch-night.png
  ```
  (Resolve the bundle id from the build settings `PRODUCT_BUNDLE_IDENTIFIER` during Task 1.)
- **Source of truth values:** `Downloads/The Perch_extracted/handoff_time_of_day/tokens.json`. Copy hex verbatim; never re-derive.
- **Commit cadence:** one commit per task. Work on a feature branch `feature/time-of-day-look-and-feel`.

---

## File Structure

**New files:**
- `ios/ThePerch/Sources/ThePerch/Views/Theme/PerchFonts.swift` — CTFontManager registration + the `Font` helpers (`.fraunces`, `.frauncesItalic`, `.inter`, `.archivoKicker`, `.jbMono`). One responsibility: typography.
- `ios/ThePerch/Sources/ThePerch/Views/Theme/PerchMark.swift` — the `.perchMark(_:)` view modifier + the `markedRuns` text-splitting helper. One responsibility: the highlight primitive.
- `ios/ThePerch/Assets.xcassets/Fonts/*.dataset/` — bundled `.ttf` files as Data Sets (no pbxproj edit; the catalog is already a build resource).
- `ios/ThePerch/ThePerchTests/PerchTimeOfDayTests.swift` — schedule-boundary tests.
- `ios/ThePerch/ThePerchTests/PerchMarkTests.swift` — marker range-finding + `marked_phrase` decode tests.

**Modified files:**
- `ios/ThePerch/Sources/ThePerch/Views/Theme/PerchTheme.swift` — revise the four `PerchPalette` values; fix `PerchTimeOfDay.current` boundary; route the `Font` helpers to bundled families; add `marker`/`rule` semantics; alias `wellness := kinetic`.
- `ios/ThePerch/Sources/ThePerch/App/<@main app>.swift` — call `PerchFonts.registerAll()` in `init()`.
- `ios/ThePerch/Sources/ThePerch/Views/App/MainTabView.swift` — 600ms palette cross-fade + reduce-motion guard + `PERCH_TOD_OVERRIDE`.
- `ios/ThePerch/Sources/ThePerch/Views/App/TodayTab.swift` — hero strip (320→188pt, ink greeting, keep video, 2-line→212pt), tightened Today density (14pt side / 12pt gap).
- `ios/ThePerch/Sources/ThePerch/Views/Cards/DailyInsightCard.swift` — render the marker on the working phrase via `.perchMark`; card radius 16→18; Fraunces/Archivo/mono fonts.
- `ios/ThePerch/Sources/ThePerch/Views/Cards/NutritionHomeCard.swift` — ring = `kinetic`, mono macro figures, hairline rules.
- `ios/ThePerch/Sources/ThePerch/Models/Insight.swift` — add `var markedPhrase: String?` (decodes `data.marked_phrase`).
- `agents/health-integrations/biochecha_dynamic_insight.py` — extend the prompt + upsert to emit `marked_phrase`.
- Remaining tabs (PART B): `HealthTab.swift`, `HubTab.swift`, `SearchView.swift`, `SettingsTab.swift`, `AuthView.swift`, `CardGalleryView.swift` — migrate `PerchTheme.*` → palette per the recipe.

---

# PART A — Foundation & Today feed

## Task 1: Bundle the four type families (Data Sets + runtime registration)

**Files:**
- Create: `ios/ThePerch/Assets.xcassets/Fonts/` data sets (below)
- Create: `ios/ThePerch/Sources/ThePerch/Views/Theme/PerchFonts.swift`
- Modify: the `@main` app struct (locate with `grep -rn "@main" ios/ThePerch/Sources`)

- [ ] **Step 1: Download the variable TTFs from Google Fonts (OFL).** Run from repo root:

```bash
mkdir -p /tmp/perchfonts && cd /tmp/perchfonts
base="https://github.com/google/fonts/raw/main/ofl"
curl -fL -o Fraunces.ttf        "$base/fraunces/Fraunces%5BSOFT%2CWONK%2Copsz%2Cwght%5D.ttf"
curl -fL -o Fraunces-Italic.ttf "$base/fraunces/Fraunces-Italic%5BSOFT%2CWONK%2Copsz%2Cwght%5D.ttf"
curl -fL -o Inter.ttf           "$base/inter/Inter%5Bopsz%2Cwght%5D.ttf"
curl -fL -o Archivo.ttf         "$base/archivo/Archivo%5Bwdth%2Cwght%5D.ttf"
curl -fL -o JetBrainsMono.ttf   "$base/jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf"
ls -la *.ttf   # each should be > 100 KB
```
Expected: five non-empty `.ttf` files. If a URL 404s, list the dir: `curl -fsSL "https://api.github.com/repos/google/fonts/contents/ofl/fraunces" | grep '"name"'` and adjust the filename.

- [ ] **Step 2: Confirm the registered family/PostScript names** (so `Font.custom` uses the right string):

```bash
for f in /tmp/perchfonts/*.ttf; do echo "== $f =="; \
  python3 - "$f" <<'PY'
import sys
from fontTools.ttLib import TTFont   # pip install fonttools if missing
n=TTFont(sys.argv[1])["name"]
print("family   :", n.getDebugName(1))
print("fullname :", n.getDebugName(4))
print("postscript:", n.getDebugName(6))
PY
done
```
Expected names: `Fraunces`, `Inter`, `Archivo`, `JetBrains Mono`. Italic shares family `Fraunces`. Record the exact strings — they feed Step 5.

- [ ] **Step 3: Create the Data Sets** (consistent with the existing `hero-afternoon-video.dataset`). For each family create `ios/ThePerch/Assets.xcassets/Fonts/<Name>.dataset/Contents.json` and copy the ttf beside it. Example for Fraunces (repeat for `Fraunces-Italic`, `Inter`, `Archivo`, `JetBrainsMono`):

```bash
cd /Users/faresende/Developer/ThePerch
for pair in "Fraunces:Fraunces.ttf" "FrauncesItalic:Fraunces-Italic.ttf" "Inter:Inter.ttf" "Archivo:Archivo.ttf" "JetBrainsMono:JetBrainsMono.ttf"; do
  name="${pair%%:*}"; file="${pair##*:}"
  dir="ios/ThePerch/Assets.xcassets/Fonts/${name}.dataset"
  mkdir -p "$dir"
  cp "/tmp/perchfonts/${file}" "$dir/${file}"
  cat > "$dir/Contents.json" <<JSON
{
  "info" : { "author" : "xcode", "version" : 1 },
  "data" : [ { "idiom" : "universal", "filename" : "${file}" } ]
}
JSON
done
find ios/ThePerch/Assets.xcassets/Fonts -type f | sort
```
Expected: five `.dataset` dirs each with a `Contents.json` + `.ttf`. NSDataAsset names will be `Fraunces`, `FrauncesItalic`, `Inter`, `Archivo`, `JetBrainsMono`.

- [ ] **Step 4: Write `PerchFonts.swift`** — runtime registration + helpers:

```swift
import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#endif

/// Bundled type families for the time-of-day system. Registered at launch
/// from Asset Catalog Data Sets via CoreText, so no Info.plist/UIAppFonts
/// or pbxproj edits are needed. Reference families by the names CoreText
/// reports (see PerchFonts registration log).
enum PerchFonts {
    /// Asset name → expected family name (verified in PerchFontsTests/log).
    private static let assets = ["Fraunces", "FrauncesItalic", "Inter", "Archivo", "JetBrainsMono"]

    /// Call once, early, before any view renders (app init).
    static func registerAll() {
        for asset in assets {
            guard let data = NSDataAsset(name: asset)?.data else {
                assertionFailure("Missing font Data Set: \(asset)"); continue
            }
            guard let provider = CGDataProvider(data: data as CFData),
                  let font = CGFont(provider) else { continue }
            var err: Unmanaged<CFError>?
            if !CTFontManagerRegisterGraphicsFont(font, &err) {
                // Already-registered is fine on hot reload; log others.
                if let e = err?.takeRetainedValue() { print("Font register \(asset): \(e)") }
            }
        }
    }

    // Family names CoreText registers (confirm via Task 1 Step 2).
    static let frauncesFamily = "Fraunces"
    static let interFamily     = "Inter"
    static let archivoFamily   = "Archivo"
    static let monoFamily      = "JetBrains Mono"
}

extension Font {
    /// Fraunces upright (display + tabular figures). Weight via .fontWeight().
    static func fraunces(_ size: CGFloat) -> Font { .custom(PerchFonts.frauncesFamily, size: size) }
    /// Fraunces italic — the brand voice (greeting, biochecha, card titles).
    static func frauncesItalic(_ size: CGFloat) -> Font {
        .custom(PerchFonts.frauncesFamily, size: size).italic()
    }
    /// Inter — running body copy.
    static func inter(_ size: CGFloat) -> Font { .custom(PerchFonts.interFamily, size: size) }
    /// Archivo 700 — uppercase kicker labels (apply .tracking(0.14em*size) + uppercase at the call site).
    static func archivoKicker(_ size: CGFloat) -> Font {
        .custom(PerchFonts.archivoFamily, size: size).weight(.bold)
    }
    /// JetBrains Mono — timestamps + macro figures.
    static func jbMono(_ size: CGFloat) -> Font { .custom(PerchFonts.monoFamily, size: size) }
}
```

- [ ] **Step 5: Register at launch.** Find the entry point (`grep -rn "@main" ios/ThePerch/Sources`) and call registration in its `init()` before the first scene renders:

```swift
@main
struct ThePerchApp: App {
    init() {
        PerchFonts.registerAll()
        // ...existing init...
    }
    // ...existing body...
}
```

- [ ] **Step 6: Build + verify fonts load.** Run the build command. Then temporarily add to the app `init()` (remove after verifying):

```swift
print("FONTS:", UIFont.familyNames.filter { ["Fraunces","Inter","Archivo","JetBrains Mono"].contains($0) })
```
Run in simulator (`xcrun simctl launch --console`). Expected console: `FONTS: ["Archivo", "Fraunces", "Inter", "JetBrains Mono"]` (order may vary). If a family is missing, the asset name or family string is wrong — fix and rebuild. Remove the debug print.

- [ ] **Step 7: Commit.**
```bash
git add ios/ThePerch/Assets.xcassets/Fonts ios/ThePerch/Sources/ThePerch/Views/Theme/PerchFonts.swift ios/ThePerch/Sources/ThePerch/App
git commit -m "feat(theme): bundle Fraunces/Inter/Archivo/JetBrains Mono via CTFontManager"
```

---

## Task 2: Revise the four palettes, the schedule boundary, and the cross-fade

**Files:**
- Modify: `ios/ThePerch/Sources/ThePerch/Views/Theme/PerchTheme.swift` (PerchPalette `static let` blocks ~1107–1168; `PerchTimeOfDay.current` ~1189–1197; add `marker`/`rule`)
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/MainTabView.swift:75,105` (cross-fade + override)
- Test: `ios/ThePerch/ThePerchTests/PerchTimeOfDayTests.swift`

**Token mapping (handoff → existing `PerchPalette`):** `bg→bg`, `surface→card`, `ink→ink`, `mute→muted`, `marker→marker (NEW)`, `rule→line`, `kinetic→kinetic`. Add `marker`. Set `wellness := kinetic` value (kills bright-hour lavender; routes the nutrition ring to kinetic with zero call-site churn). Keep `faint` derived (lighter than `muted`). `scrimDark`/`chipBg`/`error`/`heroText` stay but get re-set per palette below. `heroText` is no longer cream-on-photo — the new strip uses ink-colored greeting (Task 4), so `heroText := ink` value.

- [ ] **Step 1: Write the failing schedule test** at `ios/ThePerch/ThePerchTests/PerchTimeOfDayTests.swift`:

```swift
import Testing
@testable import ThePerch

@Suite("PerchTimeOfDay schedule (handoff boundaries)")
struct PerchTimeOfDayTests {
    @Test("11:00 is afternoon, not morning", arguments: [
        (5, PerchTimeOfDay.sunrise), (10, .sunrise),
        (11, .midday), (16, .midday),
        (17, .dusk), (21, .dusk),
        (22, .night), (4, .night), (0, .night)
    ])
    func bracket(hour: Int, expected: PerchTimeOfDay) {
        #expect(PerchTimeOfDay.bracket(forHour: hour) == expected)
    }
}
```

- [ ] **Step 2: Run it — expect FAIL** (`bracket(forHour:)` doesn't exist):
```bash
xcodebuild test -project ios/ThePerch/ThePerch.xcodeproj -scheme ThePerch -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:ThePerchTests/PerchTimeOfDayTests 2>&1 | tail -20
```
Expected: compile failure / FAIL "no member bracket".

- [ ] **Step 3: Refactor `PerchTimeOfDay.current` to use a testable `bracket(forHour:)` with the handoff boundary.** Replace the `static var current` body (PerchTheme.swift ~1189):

```swift
    /// Pure, testable hour→bracket per the handoff schedule:
    /// morning 05–10:59 · afternoon 11–16:59 · evening 17–21:59 · night 22–04:59.
    static func bracket(forHour hour: Int) -> PerchTimeOfDay {
        switch hour {
        case 5..<11:  return .sunrise   // "morning"
        case 11..<17: return .midday    // "afternoon" (11:00 moved here)
        case 17..<22: return .dusk      // "evening"
        default:      return .night
        }
    }

    static var current: PerchTimeOfDay {
        bracket(forHour: Foundation.Calendar.current.component(.hour, from: Date.now))
    }
```

- [ ] **Step 4: Run the test — expect PASS.** Same command as Step 2. Expected: all `bracket` cases pass.

- [ ] **Step 5: Add the `marker` token to `PerchPalette`.** In the struct (after `kinetic`, ~line 1020) add the stored property and init param:

```swift
    /// The single highlight per surface (Stet "marker"). Used ONLY by
    /// .perchMark — never as a fill. One per surface, on the working phrase.
    let marker: Color
```
In `init(...)` add `marker: Color` to the signature (place after `kinetic`) and `self.marker = marker`. Set `wellness := kinetic` inside the init body instead of taking it as a param? No — keep `wellness` param for source compatibility but in each palette below pass `wellness:` equal to the kinetic value.

- [ ] **Step 6: Replace the four palette `static let` blocks** with the locked handoff values. Use this `Color(hex:)` form (add the helper if absent — `grep -n "init(hex" PerchTheme.swift`; if missing, add the standard hex initializer to a `Color` extension at the bottom of the file). Morning:

```swift
    static let sunrise = PerchPalette(           // "morning" 05–10:59
        bg:        Color(hex: 0xF8E7D2),
        card:      Color(hex: 0xFCF2E2),  // handoff surface
        chipBg:    Color(hex: 0xECD9C1),  // = rule tone
        line:      Color(hex: 0xECD9C1),  // handoff rule
        ink:       Color(hex: 0x2A1B11),
        muted:     Color(hex: 0x9A7659),  // handoff mute
        faint:     Color(hex: 0x9A7659).opacity(0.7),
        kinetic:   Color(hex: 0xDD5A36),
        wellness:  Color(hex: 0xDD5A36),  // := kinetic (no lavender)
        marker:    Color(hex: 0xF2A65A),
        scrimDark: Color(hex: 0x2A1B11),
        error:     Color(hex: 0xBB4527)
    )
    static let midday = PerchPalette(            // "afternoon" 11–16:59 (HERO)
        bg:        Color(hex: 0xF3D3C6),
        card:      Color(hex: 0xFAE2D6),
        chipBg:    Color(hex: 0xE7BFB3),
        line:      Color(hex: 0xE7BFB3),
        ink:       Color(hex: 0x2A1A24),
        muted:     Color(hex: 0x8C6571),
        faint:     Color(hex: 0x8C6571).opacity(0.7),
        kinetic:   Color(hex: 0xE0563E),
        wellness:  Color(hex: 0xE0563E),
        marker:    Color(hex: 0xF0974E),
        scrimDark: Color(hex: 0x2A1A24),
        error:     Color(hex: 0xBB3D2B)
    )
    static let dusk = PerchPalette(              // "evening" 17–21:59 (purple lives here)
        bg:        Color(hex: 0xD9A39B),
        card:      Color(hex: 0xE3B4AC),
        chipBg:    Color(hex: 0xCC948D),
        line:      Color(hex: 0xCC948D),
        ink:       Color(hex: 0x2A1530),
        muted:     Color(hex: 0x7E586A),
        faint:     Color(hex: 0x7E586A).opacity(0.7),
        kinetic:   Color(hex: 0xA8497F),  // plum-magenta
        wellness:  Color(hex: 0xA8497F),
        marker:    Color(hex: 0xE08A52),
        scrimDark: Color(hex: 0x2A1530),
        error:     Color(hex: 0xB33263)
    )
    static let night = PerchPalette(             // "night" 22–04:59 — DARK (color-scheme: dark)
        bg:        Color(hex: 0x1B1626),
        card:      Color(hex: 0x241F33),
        chipBg:    Color(hex: 0x2F2942),
        line:      Color(hex: 0x2F2942),
        ink:       Color(hex: 0xECE4D6),  // cream, inverted
        muted:     Color(hex: 0x8E88A0),
        faint:     Color(hex: 0x8E88A0).opacity(0.75),
        kinetic:   Color(hex: 0xE0654A),
        wellness:  Color(hex: 0xE0654A),
        marker:    Color(hex: 0xE8B24A),
        scrimDark: Color(hex: 0x000000),
        error:     Color(hex: 0xA22C38)
    )
```
Also set `heroText` to `ink` per palette: change the stored `heroText` default (line ~1032) — make it an init-derived value `self.heroText = ink`. (Remove the hard-coded cream default; the strip greeting is now ink-colored.)

- [ ] **Step 7: Add `color-scheme` awareness for night.** Night is the only dark scheme. In `PerchTimeOfDay` add:
```swift
    var colorScheme: ColorScheme { self == .night ? .dark : .light }
```
In `MainTabView` (where the palette is injected, ~line 105) add `.preferredColorScheme(timeOfDay.colorScheme)` so system chrome (status bar, keyboards) flips at night.

- [ ] **Step 8: Add the 600ms cross-fade + debug override** in `MainTabView.swift`. At the timeOfDay resolution (~line 75) honor an override; at injection (~line 105) animate on change, guarded by reduce-motion:

```swift
    // ~line 75
    let resolvedTOD: PerchTimeOfDay = {
        if let o = ProcessInfo.processInfo.environment["PERCH_TOD_OVERRIDE"] {
            switch o { case "morning": return .sunrise; case "afternoon": return .midday
                       case "evening": return .dusk; case "night": return .night; default: break }
        }
        return timeOfDay
    }()
    let palette = PerchPalette.forTimeOfDay(resolvedTOD)
```
```swift
    // ~line 105, on the injected container
    .environment(\.perchPalette, palette)
    .environment(\.perchTimeOfDay, resolvedTOD)
    .preferredColorScheme(resolvedTOD.colorScheme)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: resolvedTOD)
```
Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion` to the view if not present. Cold launch is not animated (first value emits without a prior state).

- [ ] **Step 9: Build + visual check all four times.** Build, install, then for each `PERCH_TOD_OVERRIDE` in morning/afternoon/evening/night: launch + screenshot (see Conventions). Confirm: warm cream→peach→clay→**dark indigo** arc; **no lavender** in morning/afternoon; night cards/text legible (cream ink on indigo). 

- [ ] **Step 10: Commit.**
```bash
git add ios/ThePerch/Sources/ThePerch/Views/Theme/PerchTheme.swift ios/ThePerch/Sources/ThePerch/Views/App/MainTabView.swift ios/ThePerch/ThePerchTests/PerchTimeOfDayTests.swift
git commit -m "feat(theme): lock four palettes to handoff, dark night, marker token, 11:00 boundary, 600ms crossfade"
```

---

## Task 3: The marker primitive + data-driven Biochecha highlight

**Files:**
- Create: `ios/ThePerch/Sources/ThePerch/Views/Theme/PerchMark.swift`
- Create: `ios/ThePerch/ThePerchTests/PerchMarkTests.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Models/Insight.swift` (add `markedPhrase`)
- Modify: `ios/ThePerch/Sources/ThePerch/Views/Cards/DailyInsightCard.swift`
- Modify: `agents/health-integrations/biochecha_dynamic_insight.py`

- [ ] **Step 1: Write the failing tests** at `ios/ThePerch/ThePerchTests/PerchMarkTests.swift`:

```swift
import Testing
@testable import ThePerch

@Suite("Marker phrase splitting + decode")
struct PerchMarkTests {
    @Test("splits body into [before, marked, after] on first match")
    func splits() {
        let r = PerchMark.runs(in: "Unless you're going full rabbit, get on that before dinner.",
                               phrase: "get on that")
        #expect(r.before == "Unless you're going full rabbit, ")
        #expect(r.marked == "get on that")
        #expect(r.after == " before dinner.")
    }
    @Test("returns nil marked when phrase absent or empty → render plain")
    func absent() {
        #expect(PerchMark.runs(in: "All quiet.", phrase: "nope")?.marked == nil
                || PerchMark.runs(in: "All quiet.", phrase: "nope") == nil)
        #expect(PerchMark.runs(in: "All quiet.", phrase: "") == nil)
    }
    @Test("decodes marked_phrase from insight data JSON")
    func decode() throws {
        let json = #"{"marked_phrase":"call it a night","slot":"evening"}"#.data(using: .utf8)!
        let insight = Insight.preview(body: "…so call it a night — tomorrow opens quiet.",
                                      dataRaw: json)
        #expect(insight.markedPhrase == "call it a night")
    }
}
```

- [ ] **Step 2: Run — expect FAIL** (`PerchMark`, `Insight.preview`, `markedPhrase` undefined). Command: test with `-only-testing:ThePerchTests/PerchMarkTests`. Expected: compile failure.

- [ ] **Step 3: Create `PerchMark.swift`** — the splitter + the SwiftUI modifier:

```swift
import SwiftUI

enum PerchMark {
    struct Runs: Equatable { let before: String; let marked: String; let after: String }

    /// Split `text` around the first case-insensitive occurrence of `phrase`.
    /// Returns nil when phrase is empty or not found (→ render plain, unmarked).
    static func runs(in text: String, phrase: String) -> Runs? {
        let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, let r = text.range(of: p, options: .caseInsensitive) else { return nil }
        return Runs(before: String(text[text.startIndex..<r.lowerBound]),
                    marked: String(text[r]),
                    after:  String(text[r.upperBound...]))
    }
}

/// Baseline-anchored highlight painted BEHIND a run of text (Stet marker).
/// Stops match tokens.css: paint from 56%→93% of the line box.
struct PerchMarkBackground: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            color
                .frame(height: h * (0.93 - 0.56))
                .offset(y: h * 0.56 - h * 0.5 + (h * (0.93 - 0.56)) / 2)
        }
    }
}

extension View {
    /// Apply the marker highlight behind this text run.
    func perchMark(_ color: Color) -> some View {
        background(alignment: .center) { PerchMarkBackground(color: color) }
    }
}
```

- [ ] **Step 4: Add `Insight.markedPhrase` + a test factory** to `Insight.swift`. After `var kicker` (line ~89) add:

```swift
    /// The 2–4 word working phrase the marker highlights, if the generator
    /// emitted one in `data.marked_phrase`. Absent → render the body unmarked.
    var markedPhrase: String? {
        guard let raw = data?.raw,
              let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let s = obj["marked_phrase"] as? String,
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }

    #if DEBUG
    static func preview(body: String, dataRaw: Data?) -> Insight {
        Insight(id: UUID(), userId: UUID(), agentId: "biochecha", insightType: "daily_health_evening",
                title: nil, body: body, data: dataRaw.map { AnyJSON(raw: $0) }, sourceRefs: nil,
                generatedAt: .now, validForDate: nil, shownAt: nil, dismissedAt: nil,
                pinned: false, expiresAt: nil)
    }
    #endif
```
`AnyJSON` currently has no memberwise `init(raw:)` — add one next to its `init(from:)`:
```swift
    init(raw: Data) { self.raw = raw }
```

- [ ] **Step 5: Run the tests — expect PASS.** Same command as Step 2.

- [ ] **Step 6: Render the marker in `DailyInsightCard`.** Replace the body `Text(insight.body)` block (lines 44–49) with a runs-aware renderer using Fraunces italic, and bump card radius 16→18 (lines 55,59):

```swift
            biochechaBody(insight)
                .font(.frauncesItalic(16))
                .foregroundStyle(palette.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
```
Add the helper (uses `Text` concatenation with a `.background` only on the marked run — implemented via an `HStack` of wrapping `Text` is not line-wrap-safe, so use `AttributedString` for color + an overlay strategy). Concretely, render with `Text` concatenation and apply the highlight via a layered approach that survives wrapping:

```swift
    @ViewBuilder
    private func biochechaBody(_ insight: Insight) -> some View {
        if let phrase = insight.markedPhrase,
           let runs = PerchMark.runs(in: insight.body, phrase: phrase) {
            // Mark survives wrapping by tinting the run + an underlay drawn
            // by a TextRenderer-free approach: use Text concat for color and
            // a thin marker via attributed background (iOS 17 .backgroundStyle
            // on AttributedString run).
            Text(attributed(runs, marker: palette.marker, ink: palette.ink))
        } else {
            Text(insight.body)
        }
    }

    private func attributed(_ r: PerchMark.Runs, marker: Color, ink: Color) -> AttributedString {
        var s = AttributedString(r.before); s.foregroundColor = ink
        var m = AttributedString(r.marked)
        m.foregroundColor = ink
        m.backgroundColor = marker          // baseline band approximation for inline runs
        var a = AttributedString(r.after); a.foregroundColor = ink
        return s + m + a
    }
```
Also update the kicker to Archivo (line 28–31) and timestamp to JetBrains Mono (line 35–37):
```swift
                Text(insight.kicker)
                    .font(.archivoKicker(10.5)).tracking(1.47)   // 0.14em × 10.5
                    .textCase(.uppercase).foregroundStyle(palette.muted)
                ...
                Text(formattedTime(insight.generatedAt))
                    .font(.jbMono(10.5)).foregroundStyle(palette.faint)
```
> Note on the marker visual: `AttributedString.backgroundColor` fills the full line box, not the 56–93% band. If the band look is required at the inline level, replace `attributed(...)` with a `Text`-concatenation that colors the run and overlay a `PerchMarkBackground` clipped to the run's bounds via a `TextRenderer` (iOS 18) in a follow-up; the band is a refinement, the single-run discipline is the requirement. Verify visually in Step 8 and decide.

- [ ] **Step 7: Extend the Python generator** to emit `marked_phrase`. In `agents/health-integrations/biochecha_dynamic_insight.py`, update the system prompt (the "Write today's insight" block ~line 1195) to append:

```
After the paragraph, on a new line, output:
MARK: <the 2–4 word working phrase, copied verbatim from your paragraph, ≤22 chars, a verb phrase or the crux noun, never sentence-initial, never a bare number>
If no single phrase is clearly the crux, output: MARK: (none)
```
Then parse it where the body is read (~line 1300) and add to the upsert `data` dict (~line 1450):
```python
body_raw = completion_text.strip()
marked = None
if "\nMARK:" in body_raw:
    body_raw, _, mtail = body_raw.partition("\nMARK:")
    body_raw = body_raw.strip()
    m = mtail.strip()
    marked = None if m.lower() in ("(none)", "none", "") else m
# ...
"data": { "model": OPENAI_MODEL, "slot": slot, "winning_category": winner.category,
          "winning_score": winner.score, "fact_bundle": winner.fact_bundle,
          "marked_phrase": marked },
```
Validate against the marker rules (≤22 chars, present in body, not first word); on failure set `marked=None`. Add a one-line Python check or unit test if the repo has a generator test harness (`grep -rn "def test" agents/health-integrations`).

- [ ] **Step 8: Build + visual check.** Build, run with a seeded insight that has `marked_phrase` (use the `#Preview` or a debug insight). Confirm exactly ONE highlighted phrase on the Biochecha, greeting + everything else un-marked, and unmarked fallback when `marked_phrase` is absent.

- [ ] **Step 9: Commit.**
```bash
git add ios/ThePerch/Sources/ThePerch/Views/Theme/PerchMark.swift ios/ThePerch/ThePerchTests/PerchMarkTests.swift ios/ThePerch/Sources/ThePerch/Models/Insight.swift ios/ThePerch/Sources/ThePerch/Views/Cards/DailyInsightCard.swift agents/health-integrations/biochecha_dynamic_insight.py
git commit -m "feat(today): data-driven single marker on Biochecha working phrase"
```

---

## Task 4: Restructure the hero into the 188pt scroll-over strip (keep video)

**Files:**
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/TodayTab.swift` (`TodayHero` ~251–377; feed assembly ~52–119)

- [ ] **Step 1: Shrink the strip to 188pt and parametrize for 2-line greeting.** In `TodayHero` change both `.frame(height: 320)` (lines 264, 336) to a computed `stripHeight`. Add:
```swift
    @State private var greetingLines = 1
    private var stripHeight: CGFloat { greetingLines >= 2 ? 212 : 188 }
```

- [ ] **Step 2: Greeting → ink-colored Fraunces italic 32pt, subtle (not a colored glow).** Replace the greeting `Text` (lines 298–316):
```swift
                Text(greeting)
                    .font(.frauncesItalic(greetingLines >= 2 ? 28 : 32))
                    .foregroundColor(palette.ink)
                    .tracking(-0.6).lineSpacing(-6)
                    .lineLimit(2)
                    .background(GeometryReader { g in Color.clear
                        .onAppear { greetingLines = g.size.height > 44 ? 2 : 1 }
                        .onChange(of: greeting) { _, _ in greetingLines = g.size.height > 44 ? 2 : 1 } })
                    .shadow(color: (timeOfDay == .night ? Color.black.opacity(0.5)
                                                        : Color.white.opacity(0.3)),
                            radius: 8, x: 0, y: 1)
```
This removes the `palette.wellness` glow (lines 315–316) per the handoff.

- [ ] **Step 3: Keep the video, fade into bg across the bottom 35%.** The seam gradient (lines 273–283) already fades to `palette.bg`; tighten it for the shorter strip so it's clean by the bottom ~35%:
```swift
            LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .clear, location: 0.55),
                .init(color: palette.bg.opacity(0.4), location: 0.78),
                .init(color: palette.bg, location: 1.0),
            ], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
```
`heroBackground` (lines 342–351) is unchanged — it still plays the looping video where `heroVideoName` exists and falls back to the static image, honoring reduce-motion.

- [ ] **Step 4: Content scrolls over the strip.** In the feed assembly (TodayTab body ~line 119) increase the negative overlap so the first card rides into the strip's faded zone: change `.padding(.top, -12)` to `.padding(.top, -28)` and tighten side margins to the handoff 14pt: change `.padding(.horizontal, PerchTheme.Spacing.screenHorizontal)` (line 114) to `.padding(.horizontal, 14)`.

- [ ] **Step 5: Build + visual check all four times.** Confirm: strip is ~188pt, video still loops where present, greeting is ink-colored Fraunces italic and reads over the lower strip, content scrolls up over the faded strip edge, no leftover colored glow. Test a long name (set display name "Alexandra") → greeting steps to 28pt / 2 lines and strip grows to 212pt; verify no third line and no truncation.

- [ ] **Step 6: Commit.**
```bash
git add ios/ThePerch/Sources/ThePerch/Views/App/TodayTab.swift
git commit -m "feat(today): 188pt scroll-over hero strip, ink greeting, 2-line→212pt, keep video"
```

---

## Task 5: Today density + figure/kicker conformance (Nutrition, Agenda, eyebrows)

**Files:**
- Modify: `ios/ThePerch/Sources/ThePerch/Views/Cards/NutritionHomeCard.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/TodayTab.swift` (card stack gap; the Today eyebrow/kicker + agenda primitives — `grep -n "TodayEyebrow\|cardStack\|TodayPhrase" TodayTab.swift`)

- [ ] **Step 1: Tighten the Today card-stack gap to 12pt.** In TodayTab the feed `LazyVStack(spacing: PerchTheme.Spacing.cardStack)` (line 62) — change to `spacing: 12`. (Local literal so other tabs' `Spacing.cardStack` is untouched; whole-app density is handled in PART B.)

- [ ] **Step 2: Nutrition ring + figures.** In `NutritionHomeCard.swift` (`grep -n "wellness\|Fraunces\|monospacedDigit\|Circle()\|stroke" NutritionHomeCard.swift`): ensure the ring stroke uses `palette.kinetic` (it already resolves to kinetic via the alias, but replace any explicit `palette.wellness` with `palette.kinetic` for clarity); set the center kcal total to `.fraunces(23).weight(.medium)` with `.monospacedDigit()`; set macro figures to `.jbMono(11.5)` with the `current` in `palette.ink` and `/ target` in `palette.muted`; ensure row separators are 1px `palette.line` hairlines and macro bar fill is `palette.kinetic`.

- [ ] **Step 3: Kickers app-of-Today → Archivo.** Where Today renders eyebrows/kickers (the `TodayEyebrow` primitive and the agenda card kicker), route the font to `.archivoKicker(10.5)` + `.tracking(1.47)` + `.textCase(.uppercase)` + `palette.muted`, and timestamps to `.jbMono(11)`. The leading live-dot stays `palette.kinetic` (Nutrition / active agenda) per the handoff; static cards omit it.

- [ ] **Step 4: Numbers set instantly; only ring arc + macro bars animate.** Verify no number uses a count-up animation; the ring arc + macro bar widths grow from 0 over `PerchTheme`'s base duration with the `cubic-bezier(0.2,0.8,0.2,1)`-equivalent easing (`.timingCurve(0.2,0.8,0.2,1, duration: 0.32)`).

- [ ] **Step 5: Build + visual check.** Confirm tight rhythm (12pt gaps, 14pt margins), Fraunces hero figure + mono macros, Archivo kickers, hairline rules, ring in kinetic. At least the top of a second card shows under the greeting (handoff §7).

- [ ] **Step 6: Commit.**
```bash
git add ios/ThePerch/Sources/ThePerch/Views/Cards/NutritionHomeCard.swift ios/ThePerch/Sources/ThePerch/Views/App/TodayTab.swift
git commit -m "feat(today): density + Fraunces/Archivo/mono figure conformance"
```

---

# PART B — Whole-app propagation

The Today feed reads `PerchPalette` via `@Environment(\.perchPalette)`; the other tabs read **static** `PerchTheme.*` (adaptive light/dark, not time-of-day). To make the whole app re-tint with the hour (and go dark at night) we migrate each remaining surface from `PerchTheme.*` to the environment palette. This is mechanical; the **migration recipe is fixed** so each tab is a recipe-application + verification, not a fresh design.

### Migration recipe (apply per file)

1. Add `@Environment(\.perchPalette) private var palette` to each `View` in the file that currently uses `PerchTheme.*` colors.
2. Replace color references using this table (the only allowed mapping):

| `PerchTheme.*` | → palette token |
|---|---|
| `.background` | `palette.bg` |
| `.cardBackground` | `palette.card` |
| `.cardInnerBackground` / `.cardHover` | `palette.chipBg` |
| `.textPrimary` | `palette.ink` |
| `.textSecondary` | `palette.muted` |
| `.textTertiary` | `palette.faint` |
| `.accent` | `palette.kinetic` |
| `.wellness` / `.success` | `palette.kinetic` (lavender/sage retired) |
| `.border` / `.divider` | `palette.line` |
| `.error` | `palette.error` |
| `.warning` | `palette.warn` |
| macro colors | keep (semantic), but verify contrast on the dark night `bg` |

3. Leave `PerchTheme.Font.*` / `Spacing.*` / `Icon.*` as-is in PART B (typography migration to bundled fonts beyond Today is out of scope for this pass unless trivial).
4. Do **not** introduce a second marker anywhere — the marker is Today-Biochecha-only this pass.
5. Build; run the simulator at `PERCH_TOD_OVERRIDE=night` AND one light time; screenshot; confirm no unreadable text (the #1 risk is a hardcoded `.black`/`.white`/`Color(white:)` that doesn't flip — grep each file for these and route through `palette`).

### Task 6: Migrate `SettingsTab.swift`
- [ ] Apply the recipe to `ios/ThePerch/Sources/ThePerch/Views/App/SettingsTab.swift`. Build + screenshot night & midday. Commit `style(settings): time-of-day palette`.

### Task 7: Migrate `SearchView.swift`
- [ ] Apply the recipe to `ios/ThePerch/Sources/ThePerch/Views/App/SearchView.swift`. Build + screenshot night & midday. Commit `style(search): time-of-day palette`.

### Task 8: Migrate `HubTab.swift`
- [ ] Apply the recipe to `ios/ThePerch/Sources/ThePerch/Views/App/HubTab.swift` (largest; note the existing map "marker" at line 1364 is unrelated — leave it). Build + screenshot night & midday. Commit `style(hub): time-of-day palette`.

### Task 9: Migrate `HealthTab.swift`
- [ ] Apply the recipe to `ios/ThePerch/Sources/ThePerch/Views/App/HealthTab.swift`. It already references Fraunces at several lines — route those through the bundled `.fraunces*` helpers while here. Build + screenshot night & midday. Commit `style(health): time-of-day palette + Fraunces`.

### Task 10: Migrate `AuthView.swift` + `CardGalleryView.swift`
- [ ] Apply the recipe to both. AuthView shows pre-login (no MainTabView wrapper) — inject a palette explicitly: wrap its root in `.environment(\.perchPalette, PerchPalette.forTimeOfDay(.current))`. Build + screenshot. Commit `style(auth,gallery): time-of-day palette`.

### Task 11: Migrate the tab-bar chrome in `MainTabView.swift`
- [ ] The custom tab bar / chrome (`@Environment(\.perchPalette)` already present at lines 584/624/693/939) — audit those subviews for residual `PerchTheme.*` and hardcoded colors; route through `palette`. Confirm the selected/unselected tab icons read on the dark night `bg`. Build + screenshot all four times. Commit `style(tabbar): time-of-day palette`.

### Task 12: Hardcoded-color audit + final four-times QA
- [ ] **Step 1:** Sweep for colors that won't flip at night:
```bash
grep -rn "Color.black\|Color.white\|Color(white:\|\.black)\|\.white)\|UIColor.black\|UIColor.white\|#FFFFFF\|0xFFFFFF" ios/ThePerch/Sources/ThePerch/Views | grep -v "Tests"
```
Triage each hit: scrims/overlays that should stay fixed are fine; text/fills must route through `palette`.
- [ ] **Step 2:** Build + run all four `PERCH_TOD_OVERRIDE` values across every tab; screenshot to `/tmp/perch-qa/`. Acceptance: continuous warm arc by day, genuinely dark indigo at night with legible cream text everywhere; no lavender in morning/afternoon; exactly one marker (Today/Biochecha) and none elsewhere; Fraunces/Archivo/mono visibly rendering on Today.
- [ ] **Step 3:** Run the full test suite (`xcodebuild test ...`) — expect PASS. Commit `test: time-of-day look-and-feel QA pass`.

---

## Self-Review notes (against the handoff)

- **tokens.json values** — Task 2 Step 6 copies every hex verbatim; night carries `color-scheme: dark` (Task 2 Step 7). ✓
- **Schedule 11:00 boundary** — Task 2 Steps 1–4 (tested). ✓
- **600ms cross-fade + reduce-motion + hard cold launch** — Task 2 Step 8. ✓
- **Marker: one per surface, working phrase, or none; never duplicated** — Task 3 (data-driven, unmarked fallback) + PART B rule 4. ✓
- **Greeting fixed strings, never marked, Fraunces italic, 2-line→212pt** — already-correct strings (PerchTimeOfDay.greeting) + Task 4 Steps 1–2. ✓
- **Header strip 188pt full-bleed, fades to bg, content scrolls over, video kept** — Task 4. ✓
- **Kickers Archivo 700 uppercase 0.14em; mono timestamps/figures; Fraunces hero figures** — Tasks 3 & 5. ✓
- **kinetic = actions only; marker = the one highlight; purple only at evening; no bright-hour lavender** — Task 2 (wellness:=kinetic, evening kinetic plum). ✓
- **Density: radius 18, ~15–16 padding, 12 gap, 14 margins, hairline rules** — Tasks 3 (radius 18), 4 (14 margins), 5 (12 gap, hairlines). ✓
- **Fonts bundled (all four)** — Task 1. ✓
- **Whole-app reskin incl. dark night** — PART B. ✓
- **Strips are placeholders → keep the app's real illustrations** — the plan keeps `heroImageName`/`heroVideoName` assets and does NOT import the handoff placeholder PNGs. ✓ (Final per-time art is a separate art-commission task, out of scope.)
