# UI/UX Overhaul - The Perch iOS App

## 1. Skeleton Loading (ShimmerEffect.swift)

Replaced all `ProgressView()` spinners with shimmer skeleton placeholders that match each card type's shape.

**New file:** `Views/Helpers/ShimmerEffect.swift`
- `ShimmerModifier` - Animating gradient overlay that sweeps left-to-right continuously
- `SkeletonLine`, `SkeletonCircle`, `SkeletonRect` - Reusable skeleton shape primitives
- Card-specific skeletons: `SkeletonSingleValueCard`, `SkeletonChartCard`, `SkeletonCaloriesCard`, `SkeletonMacrosCard`, `SkeletonDeliveryCard`, `SkeletonEventCard`, `SkeletonBookmarkCard`
- Section-level skeletons: `SkeletonHealthSection`, `SkeletonDeliveriesSection`, `SkeletonCalendarSection`, `SkeletonHomeSection`

**Updated views:** HomeView, HealthView, DeliveriesView, CalendarView, BookmarksView, AdminView, LegalView, HomeHighlightsView, MainTabView (generic fallback)

## 2. Animations (PerchTheme.swift)

**Card Appear Animation** - Staggered fade + slide-up per card index:
- `.cardAppear(index:appeared:)` view modifier with spring animation, 60ms stagger per card
- Applied to HomeView smart-ordered cards, HealthView cards, DeliveriesView active cards, CalendarView events

**Value Count-Up** - `AnimatedNumber` view for smooth numeric transitions

**Card Tap Scale** - `CardPressStyle` button style with subtle 0.97x scale on press + haptic feedback
- Applied to EventCard, BookmarkCard, DeliveryCard, HealthView chart buttons

**Page Indicator** - Active tab dot animates to capsule shape (8px -> 20px wide) with spring physics

**Smooth Tab Transitions** - `.animation(.easeInOut)` on TabView selection

## 3. Card Improvements

### CaloriesCard
- Animated circular progress ring that fills from 0 to target on appear
- Angular gradient on the ring (from 50% opacity to full color)
- Count-up animation for the consumed calorie number
- `.contentTransition(.numericText())` for smooth digit changes

### MacrosCard
- Gradient-filled progress bars: green gradient for protein, blue for carbs, yellow for fat
- Animated bar fill from 0 to current value on appear
- Over-target bars still show error red

### DeliveryCard
- Animated timeline connector line that draws from left to active step
- Step dots now contain SF Symbol icons (cart, shippingbox, truck, checkmark)
- Gradient on the active connector line
- `CardPressStyle` for tap feedback

### SingleValueCard
- Larger value display: 24pt bold rounded (up from 18pt)
- Stacked layout: label above value (vertical) instead of inline
- Trend badge with colored background pill (e.g., "+2.3%" on green)
- `.contentTransition(.numericText())`

### ChartCard
- Already had gradient fill under line chart (AreaMark) - no changes needed

## 4. Haptic Feedback (PerchHaptics)

**New enum:** `PerchHaptics` in PerchTheme.swift with `.light()`, `.medium()`, `.selection()`, `.success()` methods.

- **Pull-to-refresh**: Medium haptic on start, success haptic on complete (all section views)
- **Tab switch**: Selection haptic on page swipe (MainTabView)
- **Card taps**: Light haptic via `CardPressStyle` (EventCard, BookmarkCard, DeliveryCard, HealthView chart cards)
- **Collapsible sections**: Light haptic on expand/collapse (DeliveriesView completed section)

## Files Modified

| File | Changes |
|------|---------|
| `Views/Theme/PerchTheme.swift` | Added `.cardAppear()`, `.cardTapScale()`, `PerchHaptics`, `AnimatedNumber`, `CardPressStyle` |
| `Views/Helpers/ShimmerEffect.swift` | **NEW** - Shimmer modifier + all skeleton card/section templates |
| `Views/Cards/CaloriesCard.swift` | Animated progress ring, angular gradient, count-up animation |
| `Views/Cards/MacrosCard.swift` | Gradient progress bars (green/blue/yellow), animated fill |
| `Views/Cards/DeliveryCard.swift` | Animated timeline, step icons, CardPressStyle |
| `Views/Cards/SingleValueCard.swift` | Larger value (24pt), stacked layout, trend badge pill |
| `Views/Cards/EventCard.swift` | CardPressStyle |
| `Views/Cards/BookmarkCard.swift` | CardPressStyle |
| `Views/App/MainTabView.swift` | Haptic on tab switch, capsule page indicator, skeleton fallback |
| `Views/App/HomeHighlightsView.swift` | Skeleton loading |
| `Views/Sections/HomeView.swift` | Skeleton loading, staggered card appear, haptics |
| `Views/Sections/HealthView.swift` | Skeleton loading, staggered card appear, haptics |
| `Views/Sections/DeliveriesView.swift` | Skeleton loading, card appear animation, haptics |
| `Views/Sections/CalendarView.swift` | Skeleton loading, card appear animation, haptics, CardPressStyle on rows |
| `Views/Sections/BookmarksView.swift` | Skeleton loading, haptics |
| `Views/Sections/AdminView.swift` | Skeleton loading, haptics |
| `Views/Sections/LegalView.swift` | Skeleton loading, haptics |
