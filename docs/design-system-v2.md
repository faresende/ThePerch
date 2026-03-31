# The Perch — Design System v2 (Icon-Aligned)

**North Star:** The entire app should feel like it “belongs inside” the new app icon.

Icon language (chosen direction):
- **Form:** inverted Y-shaped branch (stem pointing up-right, two prongs down-left)
- **Material:** cool steel at the tips → warm amber-gold at the junction
- **Energy:** soft amber glow around the junction
- **Field:** dark charcoal background (not pure black)

Design principle: **Charcoal + Steel + Amber**.
- Charcoal is the canvas (quiet, premium, modern).
- Steel is the structure (precision, calm, clarity).
- Amber is the life (focus, freshness, importance).

This document defines the complete visual system so the UI reads as: **dim charcoal surfaces with precise steel detail, energized by controlled amber glow**.

---

## 1) Color System Update

### 1.1 Palette (authoritative tokens)

These are the “real” brand colors derived from the icon story. Everything else (tints, borders, glows) is computed or picked to harmonize.

#### Core neutrals (Charcoal family)
- **Charcoal 950 (App background / field)**
  - Dark: `#121213`
  - Light: `#F8F7F5` (keep current warm-white; it already fits)

- **Charcoal 900 (Card surface)**
  - Dark: `#191A1B`
  - Light: `#FFFFFF`

- **Charcoal 850 (Inner surface / rows / chips)**
  - Dark: `#212225`
  - Light: `#F2F1EF`

- **Charcoal 800 (Hover/pressed)**
  - Dark: `#26272B`
  - Light: `#EDECEB`

#### Brand accents
- **Amber Gold (junction / primary accent)**
  - Dark: `#F2B04A`  (warm amber-gold; not orange, not lemon)
  - Light: `#C8840A` (deeper to hold contrast on white)

- **Steel Gray (tip metal / secondary accent)**
  - Dark: `#A7ADB6`  (cool steel)
  - Light: `#5B616B` (slate-steel for light mode UI)

#### Text (warm whites + warm grays)
- **Text / Primary**
  - Dark: `#F2F0EB` (warm white)
  - Light: `#1A1A1A`

- **Text / Secondary**
  - Dark: `#A29D95` (warm gray)
  - Light: `#6B6B70`

- **Text / Tertiary**
  - Dark: `#7D7871` (warm dim)
  - Light: `#8E8E93`

#### Functional colors (harmonized)
Keep semantics, but bias slightly warmer so they don’t feel like alien system colors.
- **Success**
  - Dark: `#38C97A`
  - Light: `#1D8A3C`

- **Warning** (distinct from amber accent; more “burnt orange”) 
  - Dark: `#F0A24A`
  - Light: `#C47F0A`

- **Error**
  - Dark: `#E85A5A`
  - Light: `#C42B2B`

#### Borders & separators (steel-tinted)
- **Border (default)**
  - Dark: `#2C2E33` (slight steel bias)
  - Light: `#D8D6D3`

#### Glow colors
Glow is the icon’s emotional signature. It must be **rare, purposeful, and layered**.
- **Amber Glow / Ambient**
  - Dark: `#F2B04A` @ 14% alpha (`0.14`)
  - Light: **transparent** (no glow in light mode; keep UI crisp)

- **Amber Glow / Attention**
  - Dark: `#F2B04A` @ 22% alpha (`0.22`)

- **Amber Glow / Urgent**
  - Dark: `#F2B04A` @ 34% alpha (`0.34`)


### 1.2 Mapping: current `PerchTheme` → v2

Below is a 1:1 replacement map. The goal is minimal churn in call sites while changing the aesthetic.

| Token | Current Dark | Proposed Dark | Current Light | Proposed Light | Notes |
|---|---:|---:|---:|---:|---|
| `background` | `#0D0D0E` | `#121213` | `#F8F7F5` | `#F8F7F5` | Background should be charcoal, not true black. |
| `cardBackground` | `#171718` | `#191A1B` | `#FFFFFF` | `#FFFFFF` | Slightly warmer + more premium charcoal. |
| `cardInnerBackground` | `#1F1F20` | `#212225` | `#F2F1EF` | `#F2F1EF` | Add steel-tinted depth. |
| `cardHover` | `#262627` | `#26272B` | `#EDECEB` | `#EDECEB` | Dark hover shifts cooler/steelier. |
| `textPrimary` | `#F2F2F2` | `#F2F0EB` | `#1A1A1A` | `#1A1A1A` | Warm the white to match amber vibe. |
| `textSecondary` | `#8A8A8F` | `#A29D95` | `#6B6B70` | `#6B6B70` | Replace neutral gray with warm gray. |
| `textTertiary` | `#737378` | `#7D7871` | `#8E8E93` | `#8E8E93` | Warm dim, still readable. |
| `accent` | `#F5AD26` | `#F2B04A` | `#D4940D` | `#C8840A` | Less orange, more gold. |
| `accentForeground` | `#1F1400` | `#1A1206` | `#261A00` | `#261A00` | Slightly more neutral brown-black on amber. |
| `accentMuted` | (alpha) | (alpha) | (alpha) | (alpha) | Keep behavior; recompute from new accent. |
| `accentGlow` | amber @ 0.13 | amber @ 0.14 | transparent | transparent | Slight bump for presence on charcoal. |
| `success` | `#38BF73` | `#38C97A` | `#1D8A3C` | `#1D8A3C` | Slightly fresher green in dark. |
| `warning` | `#EB9926` | `#F0A24A` | `#C47F0A` | `#C47F0A` | Shift away from accent to burnt orange. |
| `warningBackground` | alpha tint | alpha tint | alpha tint | alpha tint | Same logic with new warning. |
| `error` | `#E65454` | `#E85A5A` | `#C42B2B` | `#C42B2B` | Slightly softer red in dark. |
| `border` | `#29292B` | `#2C2E33` | `#D8D6D3` | `#D8D6D3` | Steel-tinted border. |


### 1.3 New tokens to add (needed for full icon alignment)

Add these to `PerchTheme` to avoid UI teams inventing ad-hoc colors:

- `static var steel: Color` — secondary accent
- `static var steelMuted: Color` — steel @ low alpha for dividers, icon strokes
- `static var divider: Color` — subtle separators (esp. inside cards)
- `static var focusRing: Color` — amber ring for focus/selection (dark mode only)

Proposed values:
- `steel`:
  - Dark: `#A7ADB6`
  - Light: `#5B616B`
- `steelMuted`:
  - Light: steel @ 10% alpha
  - Dark: steel @ 16% alpha
- `divider`:
  - Light: `#E5E1DB`
  - Dark: `#2A2B2F`
- `focusRing`:
  - Light: transparent
  - Dark: `#F2B04A` @ 28% alpha


### 1.4 Where glow is allowed (and where it is not)

Glow is *not* a default shadow. It is an “energy cue.”

Use glow on:
- **Hero card** (top card of the stack)
- **Freshly updated data** (e.g., “updated just now”)
- **Primary action states** (selected tab, active filter, selected segment)
- **Urgency** (warning stale tier should glow subtly; critical uses warning color border)

Do **not** use glow on:
- Every card by default (it becomes wallpaper)
- Secondary UI chrome (list separators, small buttons)
- Error states (use red; glow reads like “positive energy”)

---

## 2) Glow Language (the signature)

### 2.1 Glow levels

**Level 0 — None**
- Default for 80%+ of UI.

**Level 1 — Ambient (subtle halo)**
- Purpose: make a surface feel “alive” without demanding attention.
- Use: hero card background, selected tab, “fresh” content.
- Appearance: soft, wide radius, low alpha.

**Level 2 — Attention (notice me)**
- Purpose: highlight interactive selection or a new event.
- Use: focused controls (segmented pickers, search focus), featured card, “warning stale” border.
- Appearance: slightly tighter radius + brighter alpha.

**Level 3 — Urgent (only for system urgency)**
- Purpose: force attention for time-critical info.
- Use: only in critical alerts *if you keep amber*; otherwise prefer warning color.
- Appearance: narrow-ish radius, highest alpha, may pulse (but respect Reduce Motion).

### 2.2 SwiftUI implementation (standard modifiers)

Add a reusable modifier that composes **two shadows** + optional gradient overlay. This yields an icon-like glow instead of a cheap drop-shadow.

```swift
enum PerchGlowLevel {
    case none
    case ambient
    case attention
    case urgent
}

extension View {
    func perchGlow(_ level: PerchGlowLevel) -> some View {
        modifier(PerchGlowModifier(level: level))
    }
}

private struct PerchGlowModifier: ViewModifier {
    let level: PerchGlowLevel
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        guard colorScheme == .dark else { return AnyView(content) }

        let (alpha, r1, r2): (Double, CGFloat, CGFloat) = {
            switch level {
            case .none: return (0.0, 0, 0)
            case .ambient: return (0.14, 18, 6)
            case .attention: return (0.22, 16, 5)
            case .urgent: return (0.34, 14, 4)
            }
        }()

        if level == .none {
            return AnyView(content)
        }

        return AnyView(
            content
                .shadow(color: PerchTheme.accent.opacity(alpha), radius: r1, x: 0, y: 0)
                .shadow(color: Color.black.opacity(0.35), radius: r2, x: 0, y: 2)
        )
    }
}
```

### 2.3 When a card glows (rules)

- **Hero card**: always **Ambient**.
- **Featured cardProminence**: border + **Ambient**.
- **Active / Selected** card (tapped, expanded, currently playing, etc.): **Attention** while active.
- **Stale tier warning**: keep current animated border but add **Ambient** glow behind it (dark mode only).
- **Critical** stale tier: do *not* amber glow—use **warning** border + (optional) warning-tinted shadow.

---

## 3) Typography Adjustments

Current typography is strong (system + rounded numeric variants). Keep it, but refine the “warm premium” vibe:

### 3.1 Type rules
- Keep **SF Pro** as base (system font).
- Keep **rounded numeric** variants for metrics (this is very on-brand for “soft technology”).
- Increase perceived warmth by:
  - using `textPrimary` warm white in dark mode (done via token)
  - using **steel** for secondary iconography in dark mode (instead of plain gray)

### 3.2 Numeric emphasis
Make numbers feel like “junction energy” only when they matter.
- Default metric numbers: **textPrimary**.
- Key metrics (hero, selected detail): **accent**.
- Secondary metrics: **textSecondary** or **steel**.

Recommendation:
- Reserve `accent` for **one** number per card (the headline), not every metric.

No font size changes required yet. If anything: consider bumping `caption` weight to `.medium` in dark mode contexts where the warm gray gets soft, but this is optional.

---

## 4) Card Style Updates

### 4.1 Card construction (proposed)
Cards should read like **charcoal slabs with steel edges**. The icon is a metal branch with glowing junction; cards should feel like “machined” surfaces.

Changes:
- Keep corner radius `18` (it’s modern and matches the soft glow language).
- Make border slightly more steel-tinted (`#2C2E33`).
- Reduce default glow usage: **remove amber glow from all cards by default**.
- Default cards get a neutral depth shadow only; glow is applied selectively via `perchGlow`.

### 4.2 Hero card
Hero card should be the place where the icon’s junction “energy” lives.
- Add a subtle top-edge gradient hint (steel→amber) in dark mode.
- Add Ambient glow.

Implementation idea (hero overlay):
```swift
.overlay(alignment: .top) {
    LinearGradient(
        colors: [PerchTheme.steel.opacity(0.35), PerchTheme.accent.opacity(0.45)],
        startPoint: .leading,
        endPoint: .trailing
    )
    .frame(height: 2)
    .clipShape(RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius))
}
```

### 4.3 Press/interaction
Current scale-to-0.97 is good. Add a tiny glow on press for primary cards (dark mode only):
- Use `Attention` glow while pressed.

---

## 5) Navigation & Chrome

### 5.1 Tab bar
Tab bar should feel “steel on charcoal with amber energy.”
- Background: `cardBackground` (dark charcoal slab)
- Selected icon/text: `accent`
- Unselected: `steel` (not gray)

### 5.2 Section headers
- Header text: `textPrimary`
- Supporting label: `textSecondary`
- Optional: a 2pt underline gradient (steel→amber) for primary sections on key screens.

### 5.3 Pull-to-refresh
- Spinner/tint: `accent` (it reads like “energy recharging”).
- Haptic: keep `PerchHaptics.medium()`.

### 5.4 Search bar
Search should be a “machined inset” field.
- Background: `cardInnerBackground`
- Border: `border` (or `steelMuted` when unfocused)
- Focus: `focusRing` (dark only) + `Attention` glow
- Placeholder: `textTertiary`
- Icon: `steel`

---

## 6) Motion & Transitions

Motion should reinforce “perch”: calm, intentional settling.

### 6.1 Glow pulse for loading
Allowed but subtle.
- Use a slow pulse (1.6–2.2s) on **Ambient** glow for a hero loading placeholder.
- Never pulse everything.
- Respect Reduce Motion: disable pulses.

### 6.2 Transitions
- Cards entering feed: existing spring is good.
- Expansion/collapse: use `.spring(response: 0.35, dampingFraction: 0.86)` (slightly more “settle”).

Conceptual: things “land” and settle, like a bird perching.

---

## 7) Specific SwiftUI Code Changes (exact diffs)

### 7.1 Fix file path reality
Current theme is located at:
- `ios/ThePerch/Sources/ThePerch/Views/Theme/PerchTheme.swift`

And atmosphere helper:
- `ios/ThePerch/Sources/ThePerch/Views/Helpers/TimeOfDayAtmosphere.swift`

(Original task path referenced `Sources/ThePerch/Theme/...` but the codebase currently uses `Views/Theme`.)


### 7.2 `PerchTheme.swift` — color updates + new tokens + glow modifiers

**Diff (conceptual, copy/paste exact replacements):**

```diff
--- a/ios/ThePerch/Sources/ThePerch/Views/Theme/PerchTheme.swift
+++ b/ios/ThePerch/Sources/ThePerch/Views/Theme/PerchTheme.swift
@@
 struct PerchTheme {
@@
     static var background: Color {
         adaptive(
             light: UIColor(red: 0.973, green: 0.969, blue: 0.961, alpha: 1),  // #F8F7F5
-            dark: UIColor(red: 0.05, green: 0.05, blue: 0.055, alpha: 1)      // #0d0d0e
+            dark: UIColor(red: 0.071, green: 0.071, blue: 0.075, alpha: 1)    // #121213
         )
     }
@@
     static var cardBackground: Color {
         adaptive(
             light: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),        // #FFFFFF
-            dark: UIColor(red: 0.09, green: 0.09, blue: 0.095, alpha: 1)      // #171718
+            dark: UIColor(red: 0.098, green: 0.102, blue: 0.106, alpha: 1)    // #191A1B
         )
     }
@@
     static var cardInnerBackground: Color {
         adaptive(
             light: UIColor(red: 0.949, green: 0.945, blue: 0.937, alpha: 1),  // #F2F1EF
-            dark: UIColor(red: 0.12, green: 0.12, blue: 0.125, alpha: 1)      // #1f1f20
+            dark: UIColor(red: 0.129, green: 0.133, blue: 0.145, alpha: 1)    // #212225
         )
     }
@@
     static var cardHover: Color {
         adaptive(
             light: UIColor(red: 0.929, green: 0.925, blue: 0.918, alpha: 1),  // #EDECEB
-            dark: UIColor(red: 0.15, green: 0.15, blue: 0.155, alpha: 1)      // #262627
+            dark: UIColor(red: 0.149, green: 0.153, blue: 0.169, alpha: 1)    // #26272B
         )
     }
@@
     static var textPrimary: Color {
         adaptive(
             light: UIColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1),  // #1A1A1A
-            dark: UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)       // #f2f2f2
+            dark: UIColor(red: 0.949, green: 0.941, blue: 0.922, alpha: 1)    // #F2F0EB
         )
     }
@@
     static var textSecondary: Color {
         adaptive(
             light: UIColor(red: 0.420, green: 0.420, blue: 0.440, alpha: 1),  // #6B6B70
-            dark: UIColor(red: 0.541, green: 0.541, blue: 0.561, alpha: 1)    // #8A8A8F
+            dark: UIColor(red: 0.635, green: 0.616, blue: 0.584, alpha: 1)    // #A29D95
         )
     }
@@
     static var textTertiary: Color {
         adaptive(
             light: UIColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1),  // #8E8E93
-            dark: UIColor(red: 0.451, green: 0.451, blue: 0.471, alpha: 1)    // #737378
+            dark: UIColor(red: 0.490, green: 0.471, blue: 0.443, alpha: 1)    // #7D7871
         )
     }
@@
     static var accent: Color {
         adaptive(
-            light: UIColor(red: 0.831, green: 0.580, blue: 0.051, alpha: 1),  // #D4940D
-            dark: UIColor(red: 0.96, green: 0.68, blue: 0.15, alpha: 1)       // #f5ad26
+            light: UIColor(red: 0.784, green: 0.518, blue: 0.039, alpha: 1),  // #C8840A
+            dark: UIColor(red: 0.949, green: 0.690, blue: 0.290, alpha: 1)    // #F2B04A
         )
     }
@@
     static var accentForeground: Color {
         adaptive(
             light: UIColor(red: 0.15, green: 0.10, blue: 0.0, alpha: 1),     // #261A00 — dark brown
-            dark: UIColor(red: 0.12, green: 0.08, blue: 0.0, alpha: 1)       // #1F1400 — near-black brown
+            dark: UIColor(red: 0.102, green: 0.071, blue: 0.024, alpha: 1)   // #1A1206 — near-black warm
         )
     }
@@
     static var accentGlow: Color {
         adaptive(
             light: UIColor(red: 0, green: 0, blue: 0, alpha: 0),              // transparent
-            dark: UIColor(red: 0.96, green: 0.68, blue: 0.15, alpha: 0.13)    // amber glow
+            dark: UIColor(red: 0.949, green: 0.690, blue: 0.290, alpha: 0.14) // amber glow
         )
     }
@@
     static var warning: Color {
         adaptive(
             light: UIColor(red: 0.769, green: 0.498, blue: 0.039, alpha: 1),  // #C47F0A
-            dark: UIColor(red: 0.922, green: 0.600, blue: 0.149, alpha: 1)    // #EB9926
+            dark: UIColor(red: 0.941, green: 0.635, blue: 0.290, alpha: 1)    // #F0A24A
         )
     }
@@
     static var error: Color {
         adaptive(
             light: UIColor(red: 0.769, green: 0.169, blue: 0.169, alpha: 1),  // #C42B2B
-            dark: UIColor(red: 0.90, green: 0.33, blue: 0.33, alpha: 1)       // #e65454
+            dark: UIColor(red: 0.910, green: 0.353, blue: 0.353, alpha: 1)    // #E85A5A
         )
     }
@@
     static var border: Color {
         adaptive(
             light: UIColor(red: 0.847, green: 0.839, blue: 0.827, alpha: 1),  // #D8D6D3
-            dark: UIColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)       // #29292b
+            dark: UIColor(red: 0.173, green: 0.180, blue: 0.200, alpha: 1)    // #2C2E33
         )
     }
+
+    /// Secondary accent — cool steel gray from icon tips
+    static var steel: Color {
+        adaptive(
+            light: UIColor(red: 0.357, green: 0.380, blue: 0.420, alpha: 1),  // #5B616B
+            dark: UIColor(red: 0.655, green: 0.678, blue: 0.714, alpha: 1)    // #A7ADB6
+        )
+    }
+
+    /// Low-contrast steel tint for dividers and subtle iconography
+    static var steelMuted: Color {
+        adaptive(
+            light: UIColor(red: 0.357, green: 0.380, blue: 0.420, alpha: 0.10),
+            dark: UIColor(red: 0.655, green: 0.678, blue: 0.714, alpha: 0.16)
+        )
+    }
+
+    /// Hairline dividers (especially inside cards)
+    static var divider: Color {
+        adaptive(
+            light: UIColor(red: 0.898, green: 0.882, blue: 0.859, alpha: 1),  // #E5E1DB
+            dark: UIColor(red: 0.165, green: 0.169, blue: 0.184, alpha: 1)    // #2A2B2F
+        )
+    }
+
+    /// Focus ring for selected controls (dark mode only)
+    static var focusRing: Color {
+        adaptive(
+            light: UIColor(red: 0, green: 0, blue: 0, alpha: 0),
+            dark: UIColor(red: 0.949, green: 0.690, blue: 0.290, alpha: 0.28)
+        )
+    }
 }
```


### 7.3 Update default card shadow policy

Right now `cardStyle()` includes amber glow in dark mode for *every* card. That will dilute the new glow language.

Change `CardStyleModifier` so default cards use **neutral depth only**, and glow is applied explicitly using `perchGlow(...)`.

```diff
 private struct CardStyleModifier: ViewModifier {
@@
     func body(content: Content) -> some View {
         content
             .background(PerchTheme.cardBackground)
             .cornerRadius(PerchTheme.Card.cornerRadius)
             .overlay(
                 RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                     .stroke(PerchTheme.border, lineWidth: PerchTheme.Card.borderWidth)
             )
-            .shadow(
-                color: colorScheme == .dark
-                    ? PerchTheme.accentGlow        // amber glow in dark
-                    : Color.black.opacity(0.04),   // subtle neutral in light
-                radius: colorScheme == .dark ? 16 : 8,
-                x: 0,
-                y: colorScheme == .dark ? 0 : 2
-            )
+            // Default shadow: neutral depth. Glow is applied selectively.
+            .shadow(
+                color: Color.black.opacity(colorScheme == .dark ? 0.55 : 0.06),
+                radius: colorScheme == .dark ? 10 : 8,
+                x: 0,
+                y: colorScheme == .dark ? 4 : 2
+            )
             .shadow(
                 color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.06),
                 radius: 6,
                 x: 0,
                 y: 2
             )
     }
 }
```

Yes, this is a visible change: the app will feel calmer and more “premium charcoal,” and then glow becomes meaningful.


### 7.4 Add glow modifier implementation to `PerchTheme.swift`

Append near the view extensions:

```swift
enum PerchGlowLevel {
    case none
    case ambient
    case attention
    case urgent
}

extension View {
    func perchGlow(_ level: PerchGlowLevel) -> some View {
        modifier(PerchGlowModifier(level: level))
    }
}

private struct PerchGlowModifier: ViewModifier {
    let level: PerchGlowLevel
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        guard colorScheme == .dark else { return content }

        let params: (Double, CGFloat, CGFloat) = {
            switch level {
            case .none: return (0.0, 0, 0)
            case .ambient: return (0.14, 18, 6)
            case .attention: return (0.22, 16, 5)
            case .urgent: return (0.34, 14, 4)
            }
        }()

        if level == .none { return content }

        return content
            .shadow(color: PerchTheme.accent.opacity(params.0), radius: params.1, x: 0, y: 0)
            .shadow(color: Color.black.opacity(0.35), radius: params.2, x: 0, y: 2)
    }
}
```


### 7.5 Update `HeroCardModifier` to use the steel→amber line + glow

```diff
 private struct HeroCardModifier: ViewModifier {
     let ambientColor: Color
@@
     func body(content: Content) -> some View {
         content
             .padding(.vertical, PerchTheme.Spacing.xSmall)
             .overlay(alignment: .top) {
-                // Subtle accent-colored top border (2pt)
-                RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
-                    .stroke(ambientColor.opacity(0.35), lineWidth: 2)
+                LinearGradient(
+                    colors: [PerchTheme.steel.opacity(0.35), PerchTheme.accent.opacity(0.50)],
+                    startPoint: .leading,
+                    endPoint: .trailing
+                )
+                .frame(height: 2)
+                .clipShape(RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius))
             }
+            .perchGlow(.ambient)
     }
 }
```


### 7.6 Update stale warning border to add subtle glow behind

```diff
 case .warning:
     RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
         .stroke(PerchTheme.accent.opacity(PerchMotion.prefersReduced ? 0.7 : pulseOpacity), lineWidth: 1.5)
+        .shadow(color: PerchTheme.accent.opacity(0.18), radius: 10, x: 0, y: 0)
         .onAppear {
             if !PerchMotion.prefersReduced { pulseOpacity = 0.7 }
         }
```

For `.critical`, consider switching to warning shadow (optional):

```swift
.shadow(color: PerchTheme.warning.opacity(0.20), radius: 10, x: 0, y: 0)
```


### 7.7 `TimeOfDayAtmosphere.swift` — align with steel/amber palette

Current atmosphere uses morning golds and evening violets. That’s fine, but it should now feel like **charcoal + steel + amber** rather than generic color moods.

Update the gradient colors to be *more restrained* and tied to the tokens:

- Morning: amber whisper
- Midday: near-clear warmth
- Evening: steel-blue whisper
- Night: deep steel-navy whisper

Proposed edits:

```diff
 case .morning:
-    return Color(red: 0.95, green: 0.75, blue: 0.3).opacity(0.04)
+    return Color(red: 0.949, green: 0.690, blue: 0.290).opacity(0.035) // amber whisper
 case .midday:
-    return Color(red: 0.9, green: 0.85, blue: 0.7).opacity(0.025)
+    return Color(red: 0.95, green: 0.92, blue: 0.86).opacity(0.020) // warm near-clear
 case .evening:
-    return Color(red: 0.4, green: 0.35, blue: 0.75).opacity(0.04)
+    return Color(red: 0.655, green: 0.678, blue: 0.714).opacity(0.030) // steel whisper
 case .night:
-    return Color(red: 0.1, green: 0.12, blue: 0.3).opacity(0.05)
+    return Color(red: 0.10, green: 0.12, blue: 0.18).opacity(0.045) // steel-navy
```

And bottoms:

```diff
 case .morning:
-    return Color(red: 0.9, green: 0.6, blue: 0.2).opacity(0.03)
+    return Color(red: 0.949, green: 0.690, blue: 0.290).opacity(0.025)
 case .evening:
-    return Color(red: 0.3, green: 0.25, blue: 0.6).opacity(0.03)
+    return Color(red: 0.40, green: 0.44, blue: 0.52).opacity(0.022)
 case .night:
-    return Color(red: 0.05, green: 0.08, blue: 0.25).opacity(0.04)
+    return Color(red: 0.05, green: 0.07, blue: 0.12).opacity(0.040)
```

The effect stays nearly imperceptible, but now it harmonizes with steel/amber.

---

## Implementation Task List (ordered)

1. **Update `PerchTheme` color tokens** to v2 values (background/cards/text/accent/border).
2. **Add new tokens**: `steel`, `steelMuted`, `divider`, `focusRing`.
3. **Change default `cardStyle()` shadow policy**: remove global amber glow; keep neutral depth.
4. **Add `perchGlow(_:)` modifier** and use it intentionally:
   - hero cards: `.perchGlow(.ambient)`
   - selected/active controls: `.perchGlow(.attention)`
5. **Update `HeroCardModifier`**: steel→amber top line + ambient glow.
6. **Update `StaleBorderModifier`**: warning tier gets subtle amber halo; critical uses warning tint.
7. **Retune `TimeOfDayAtmosphere`** to steel/amber whisper gradients.
8. Sweep UI for any hard-coded grays and swap to:
   - icons: `steel`
   - dividers: `divider` / `steelMuted`
   - secondary labels: `textSecondary`
9. Tab bar styling pass (if custom): selected = `accent`, unselected = `steel`, background = `cardBackground`.
10. Search styling pass: focus ring + attention glow, steel icon.

