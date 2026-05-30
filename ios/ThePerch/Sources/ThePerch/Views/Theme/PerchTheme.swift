import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Centralized theme configuration for The Perch app.
/// "Linen / Editorial" — Variant A of the Claude-Design-driven redesign.
/// Warm paper palette with a literary editorial voice: linen #F5F0E6 page,
/// barely-lifted cream #FCF8EF cards, burnt-sienna kinetic accent #C7512E,
/// dusky sage wellness #6E8D6F. Cards are chrome-free (no borders, no
/// shadows in light mode) — depth comes from tonal contrast alone.
/// Typography uses a system serif (.serif / New York) for the greeting and
/// interpretive phrases, bringing an editorial italic voice; SF Pro (default)
/// handles UI / labels / body; all numerics use .monospacedDigit() for
/// aligned columns without the glyph inflation of full monospaced fonts.
/// Dark mode mirrors on #17130F background / #1F1A15 cards preserving warmth.
struct PerchTheme {
    // MARK: - Adaptive Color Helper

    /// Creates a Color that adapts between dark and light mode.
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    // MARK: - Colors (Tangerine palette — OKLCH → sRGB)

    /// Page background — linen (light) / warm near-black (dark).
    /// Linen at #F5F0E6 is more saturated than the previous cream —
    /// it reads as real paper, not just "off-white".
    static var background: Color {
        adaptive(
            light: UIColor(red: 0.961, green: 0.941, blue: 0.902, alpha: 1),  // #F5F0E6 (linen)
            dark:  UIColor(red: 0.090, green: 0.075, blue: 0.059, alpha: 1)   // #17130F
        )
    }

    /// Card surface — softer cream, barely lifted off linen.
    /// Depth comes from this tonal contrast, not shadows or borders.
    static var cardBackground: Color {
        adaptive(
            light: UIColor(red: 0.988, green: 0.973, blue: 0.937, alpha: 1),  // #FCF8EF (soft cream)
            dark:  UIColor(red: 0.122, green: 0.102, blue: 0.082, alpha: 1)   // #1F1A15
        )
    }

    /// Inner surface / chip background — #EDE6D6 light / #2A231B dark.
    /// Used for pill chips, retailer badges, search bar, out-for-delivery
    /// row highlights.
    static var cardInnerBackground: Color {
        adaptive(
            light: UIColor(red: 0.929, green: 0.902, blue: 0.839, alpha: 1),  // #EDE6D6 (chipBg)
            dark:  UIColor(red: 0.165, green: 0.137, blue: 0.106, alpha: 1)   // #2A231B
        )
    }

    /// Card hover/pressed state — one step deeper than cardInner.
    static var cardHover: Color {
        adaptive(
            light: UIColor(red: 0.890, green: 0.859, blue: 0.784, alpha: 1),  // #E3DBC8
            dark:  UIColor(red: 0.208, green: 0.176, blue: 0.137, alpha: 1)   // #352D23
        )
    }

    /// Primary text — warm ink (light) / warm cream (dark).
    /// #1B1714 has enough warmth to read as ink, not cold black.
    static var textPrimary: Color {
        adaptive(
            light: UIColor(red: 0.106, green: 0.090, blue: 0.078, alpha: 1),  // #1B1714 (warm ink)
            dark:  UIColor(red: 0.945, green: 0.918, blue: 0.867, alpha: 1)   // #F1EADD (warm cream)
        )
    }

    /// Secondary text — stone (light) / warm tan (dark).
    /// Used for eyebrows, muted metadata.
    static var textSecondary: Color {
        adaptive(
            light: UIColor(red: 0.431, green: 0.396, blue: 0.353, alpha: 1),  // #6E655A (stone)
            dark:  UIColor(red: 0.651, green: 0.608, blue: 0.545, alpha: 1)   // #A69B8B
        )
    }

    /// Tertiary text — #A69B8B light / #6E655A dark.
    /// Freshness labels, dividers, placeholder captions.
    static var textTertiary: Color {
        adaptive(
            light: UIColor(red: 0.651, green: 0.608, blue: 0.545, alpha: 1),  // #A69B8B
            dark:  UIColor(red: 0.431, green: 0.396, blue: 0.353, alpha: 1)   // #6E655A
        )
    }

    /// Accent — burnt sienna. Kinetic signal: Now chips, time-sensitive
    /// states, high-priority, deliveries dot, travel accent. More restrained
    /// than the old tangerine — reads as editorial ink, not alert.
    static var accent: Color {
        adaptive(
            light: UIColor(red: 0.780, green: 0.318, blue: 0.180, alpha: 1),  // #C7512E (burnt sienna)
            dark:  UIColor(red: 0.886, green: 0.478, blue: 0.337, alpha: 1)   // #E27A56 (lifted for dark bg)
        )
    }

    /// Wellness accent — dusky sage. Slightly desaturated from the prior
    /// sage: reads as foliage, not neon. Used for Calendar eyebrow,
    /// Nutrition ring, Health metrics, Meds check, Email priority-low.
    static var wellness: Color {
        adaptive(
            light: UIColor(red: 0.431, green: 0.553, blue: 0.435, alpha: 1),  // #6E8D6F (dusky sage)
            dark:  UIColor(red: 0.612, green: 0.745, blue: 0.616, alpha: 1)   // #9CBE9D
        )
    }

    /// Soft wellness tint for backgrounds of "at target / success" states.
    static var wellnessMuted: Color {
        adaptive(
            light: UIColor(red: 0.431, green: 0.553, blue: 0.435, alpha: 0.12),
            dark:  UIColor(red: 0.612, green: 0.745, blue: 0.616, alpha: 0.18)
        )
    }

    /// Text color for use on accent-colored backgrounds
    static var accentForeground: Color {
        adaptive(
            light: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),        // #FFFFFF
            dark:  UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)         // #FFFFFF
        )
    }

    /// Muted accent for tinted backgrounds
    static var accentMuted: Color {
        adaptive(
            light: UIColor(red: 0.878, green: 0.365, blue: 0.220, alpha: 0.12),
            dark:  UIColor(red: 1.000, green: 0.439, blue: 0.251, alpha: 0.18)
        )
    }

    /// Accent glow — subtle citrus halo in dark mode
    static var accentGlow: Color {
        adaptive(
            light: UIColor(red: 0, green: 0, blue: 0, alpha: 0),
            dark:  UIColor(red: 1.000, green: 0.439, blue: 0.251, alpha: 0.12)
        )
    }

    /// Success — routed through `wellness` so positive signals share one
    /// calm green across the dashboard. The old bright #16A34A read as
    /// "alert, you did something" instead of "gently, well done".
    static var success: Color { wellness }

    /// Warning — amber, distinct from tangerine accent
    static var warning: Color {
        adaptive(
            light: UIColor(red: 0.851, green: 0.467, blue: 0.024, alpha: 1),  // #D97706
            dark:  UIColor(red: 1.000, green: 0.624, blue: 0.039, alpha: 1)   // #FF9F0A
        )
    }

    /// Subtle warning background tint
    static var warningBackground: Color {
        adaptive(
            light: UIColor(red: 0.851, green: 0.467, blue: 0.024, alpha: 0.12),
            dark:  UIColor(red: 1.000, green: 0.624, blue: 0.039, alpha: 0.15)
        )
    }

    /// Error — deep warm red, reserved for genuine errors only. Sits in the
    /// same warm register as the rest of the palette so it feels like the
    /// book rather than a dialog box.
    static var error: Color {
        adaptive(
            light: UIColor(red: 0.620, green: 0.247, blue: 0.188, alpha: 1),  // #9E3F30
            dark:  UIColor(red: 0.784, green: 0.463, blue: 0.408, alpha: 1)   // #C87668
        )
    }

    /// Semantic macro colors — shared across Home and Health nutrition cards.
    static var macroProtein: Color { success }
    static var macroCarbs: Color { accent }
    static var macroFat: Color {
        adaptive(
            light: UIColor(red: 0.706, green: 0.325, blue: 0.035, alpha: 1),  // #B45309 — deep amber
            dark:  UIColor(red: 0.910, green: 0.588, blue: 0.047, alpha: 1)   // #E8960C
        )
    }

    static var macroProteinGradient: [Color] {
        [macroProtein.opacity(0.72), macroProtein]
    }

    static var macroCarbsGradient: [Color] {
        [macroCarbs.opacity(0.72), macroCarbs]
    }

    static var macroFatGradient: [Color] {
        [macroFat.opacity(0.72), macroFat]
    }

    /// Line — warm hairline, used for progress-bar tracks, dividers between
    /// rows inside cards, and the TimePair top/bottom rules in TravelCard.
    /// Not a border around cards — cards remain chrome-free in Variant A.
    static var border: Color {
        adaptive(
            light: UIColor(red: 0.902, green: 0.875, blue: 0.820, alpha: 1),  // #E6DFD1
            dark:  UIColor(red: 0.169, green: 0.141, blue: 0.118, alpha: 1)   // #2B241E
        )
    }

    /// Secondary accent — cool slate blue-gray
    static var steel: Color {
        adaptive(
            light: UIColor(red: 0.392, green: 0.455, blue: 0.545, alpha: 1),  // #64748B
            dark:  UIColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1)   // #8E8E93
        )
    }

    /// Low-contrast steel tint for dividers and subtle iconography
    static var steelMuted: Color {
        adaptive(
            light: UIColor(red: 0.392, green: 0.455, blue: 0.545, alpha: 0.10),
            dark:  UIColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 0.16)
        )
    }

    /// Hairline dividers (especially inside cards)
    static var divider: Color {
        adaptive(
            light: UIColor(red: 0.867, green: 0.886, blue: 0.925, alpha: 0.70),
            dark:  UIColor(red: 0.227, green: 0.227, blue: 0.235, alpha: 0.85)
        )
    }

    /// Focus ring for selected controls
    static var focusRing: Color {
        adaptive(
            light: UIColor(red: 0.878, green: 0.365, blue: 0.220, alpha: 0.30),
            dark:  UIColor(red: 1.000, green: 0.439, blue: 0.251, alpha: 0.30)
        )
    }

    // MARK: - Typography — Linen / Editorial (Variant A)
    //
    // Two type registers coexist:
    //   1. SERIF ITALIC (design: .serif, italicised) — greeting + phrase.
    //      The editorial voice. Would ideally be Fraunces; iOS's system
    //      .serif (New York) is a clean fallback until Fraunces is bundled.
    //   2. SF PRO DEFAULT (design: .default) — UI labels, body, eyebrows.
    //      Handles the utility weight of the interface.
    // Numerics use .monospacedDigit() on either family to get column alignment
    // without the wide glyphs of full .monospaced design.

    enum Font {
        // --- Editorial serif (phrase + greeting) ---------------------
        // Fraunces is the intended family; `.serif` design falls back to
        // iOS's New York until Fraunces is bundled as a TTF resource.
        /// 34pt italic serif — full-bleed header greeting.
        static let greeting = SwiftUI.Font.system(size: 34, weight: .regular, design: .serif).italic()
        /// 30pt italic serif — alt fallback for inline greetings.
        static let greetingInline = SwiftUI.Font.system(size: 30, weight: .regular, design: .serif).italic()
        /// 22pt italic serif — the interpretive "read" phrase on every card.
        static let phrase = SwiftUI.Font.system(size: 22, weight: .regular, design: .serif).italic()
        /// 12pt italic serif — "— end of today —" signoff at bottom of feed.
        static let signoff = SwiftUI.Font.system(size: 12, weight: .regular, design: .serif).italic()

        // --- Sans UI scale ------------------------------------------
        /// 40pt bold — retained for hero numbers; unused in Variant A but
        /// kept so card implementations that still reference it compile.
        static let largeTitle = SwiftUI.Font.system(size: 40, weight: .bold, design: .default)
        /// 40pt bold alias for largeTitle.
        static let display = SwiftUI.Font.system(size: 40, weight: .bold, design: .default)
        /// 22pt semibold — dense-variant (C) greeting size; legacy.
        static let title = SwiftUI.Font.system(size: 22, weight: .semibold, design: .default)
        /// 17pt semibold — card titles, emphasised inline values.
        static let heading = SwiftUI.Font.system(size: 17, weight: .semibold, design: .default)
        /// 15pt regular — event titles, row values, body copy.
        static let body = SwiftUI.Font.system(size: 15, weight: .regular, design: .default)
        /// 14pt regular — package item names, row bodies.
        static let bodyRow = SwiftUI.Font.system(size: 14, weight: .regular, design: .default)
        /// 13pt regular — metadata, secondary body.
        static let caption = SwiftUI.Font.system(size: 13, weight: .regular, design: .default)
        /// 12pt regular — muted secondary row copy.
        static let rowSecondary = SwiftUI.Font.system(size: 12, weight: .regular, design: .default)
        /// 11pt regular — micro metadata, age stamps.
        static let micro = SwiftUI.Font.system(size: 11, weight: .regular, design: .default)
        /// 10.5pt semibold — the uppercase tracked card eyebrow label.
        static let cardEyebrow = SwiftUI.Font.system(size: 10.5, weight: .semibold, design: .default)

        // Numeric variants — serif + .monospacedDigit() for editorial tabular
        // alignment (calorie count, times, temps, tracking numbers). The serif
        // family keeps the warm literary feel; monospacedDigit() keeps the
        // columns true without the over-wide glyphs of a full mono font.
        // Numeric variants — serif (Fraunces-style) with monospacedDigit()
        // for tabular editorial alignment. Sizes match the Claude Design
        // palette-change handoff.
        static let largeTitleNumeric = SwiftUI.Font.system(size: 40, weight: .medium,   design: .serif).monospacedDigit()
        /// 28pt — Nutrition ring centre number.
        static let displayNumeric    = SwiftUI.Font.system(size: 28, weight: .medium,   design: .serif).monospacedDigit()
        /// 38pt — Weather card hero temperature.
        static let tempNumeric       = SwiftUI.Font.system(size: 38, weight: .medium,   design: .serif).monospacedDigit()
        /// 24pt — Health metric values (SLEEP / RECOVERY / READINESS).
        static let metricNumeric     = SwiftUI.Font.system(size: 24, weight: .medium,   design: .serif).monospacedDigit()
        /// 18pt serif — travel TimePair times.
        static let timePairNumeric   = SwiftUI.Font.system(size: 18, weight: .medium,   design: .serif).monospacedDigit()
        static let headingNumeric    = SwiftUI.Font.system(size: 17, weight: .semibold, design: .serif).monospacedDigit()
        static let titleNumeric      = SwiftUI.Font.system(size: 28, weight: .medium,   design: .serif).monospacedDigit()
        /// 16pt — target / remaining numerics on Nutrition.
        static let targetNumeric     = SwiftUI.Font.system(size: 16, weight: .regular,  design: .serif).monospacedDigit()
        /// 13pt — row numerics (time columns, macro values).
        static let rowNumeric        = SwiftUI.Font.system(size: 13, weight: .regular,  design: .serif).monospacedDigit()
        /// 15pt — inline tabular numbers (legacy reference).
        static let bodyNumeric       = SwiftUI.Font.system(size: 15, weight: .medium,   design: .default).monospacedDigit()
        /// 13pt — secondary tabular numbers (legacy reference).
        static let captionNumeric    = SwiftUI.Font.system(size: 13, weight: .medium,   design: .default).monospacedDigit()
        /// 11pt SF Mono — tracking numbers, age stamps ("14m", "1h"), freshness indicators.
        static let microNumeric      = SwiftUI.Font.system(size: 11, weight: .medium,   design: .monospaced)
        /// 10.5pt SF Mono — freshness label in card eyebrows ("LIVE", "2 min").
        static let freshness         = SwiftUI.Font.system(size: 10.5, weight: .regular, design: .monospaced)

        // Icon variant — use for SF Symbol sizing (passes through PerchTheme.Icon constants)
        static func icon(_ size: CGFloat) -> SwiftUI.Font {
            SwiftUI.Font.system(size: size)
        }

        // Monospaced variants — for code/data displays
        static let captionMono = SwiftUI.Font.system(size: 13, weight: .medium, design: .monospaced)
        static let microMono = SwiftUI.Font.system(size: 11, weight: .regular, design: .monospaced)
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxxSmall: CGFloat = 3
        static let xxSmall: CGFloat = 6
        static let xSmall: CGFloat = 10
        static let small: CGFloat = 14
        static let medium: CGFloat = 20
        static let mediumLarge: CGFloat = 24
        static let large: CGFloat = 28
        static let xLarge: CGFloat = 40
        static let xxLarge: CGFloat = 56
        static let xxxLarge: CGFloat = 80

        /// Vertical rhythm between stacked cards in the Today feed.
        /// 18pt per the palette-change handoff (tighter than the earlier
        /// 22pt spec to let the feed read as a continuous column).
        static let cardStack: CGFloat = 18

        /// Horizontal screen padding — 18pt per spec.
        static let screenHorizontal: CGFloat = 18
    }

    // MARK: - Card Styling (Gentler — plush 20pt corners, no chrome)

    enum Card {
        static let cornerRadius: CGFloat = 20
        static let innerCornerRadius: CGFloat = 12
        static let padding: CGFloat = 20
        static let shadowRadius: CGFloat = 5
        static let shadowOpacity: Double = 0.12
        static let borderWidth: CGFloat = 1
    }

    enum HomeCard {
        static let horizontalPadding: CGFloat = 20
        static let verticalPadding: CGFloat = 18
        static let rowSpacing: CGFloat = 10
        static let rowVerticalPadding: CGFloat = 6
        static let sectionSpacing: CGFloat = 28
        static let columnGutter: CGFloat = 10
        static let trailingColumnMinWidth: CGFloat = 96
        static let badgeMaxWidth: CGFloat = 96
        static let itemPadding: CGFloat = 10
        static let itemCornerRadius: CGFloat = 4
    }

    // MARK: - Tab Bar

    enum TabBar {
        static let height: CGFloat = 56
        static let visualRailHeight: CGFloat = 83
        static let iconSize: CGFloat = 24
        static let labelSize: CGFloat = 10
        static let glassOpacity: Double = 0.92
        static let floatingCaptureClearance: CGFloat = 0

        static var contentInsetHeight: CGFloat {
            height + bottomSafeAreaInset
        }

        static var shellContentInsetHeight: CGFloat {
            max(contentInsetHeight, visualRailHeight) + floatingCaptureClearance
        }

        private static var bottomSafeAreaInset: CGFloat {
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
            let windows = scenes.flatMap(\.windows)

            return windows.first(where: \.isKeyWindow)?.safeAreaInsets.bottom
                ?? windows.map(\.safeAreaInsets.bottom).max()
                ?? 34
        }
    }

    // MARK: - Glass Card Style

    /// Glass material card — retained for navigation chrome (tab bar).
    /// Content cards use standard cardStyle().
    static func glassCard() -> some View {
        EmptyView() // Native SwiftUI Tab/TabView gets Apple's Liquid Glass on iOS 26.
    }

    // MARK: - Icon Sizing

    enum Icon {
        static let xSmall: CGFloat = 12
        static let small: CGFloat = 16
        static let medium: CGFloat = 20
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
        static let xxLarge: CGFloat = 48
    }
}

// MARK: - Glow

enum PerchGlowLevel {
    case none
    case ambient
    case attention
    case urgent
}

private struct PerchGlowModifier: ViewModifier {
    let level: PerchGlowLevel
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if colorScheme != .dark || level == .none {
            content
        } else {
            let alpha: Double = {
                switch level {
                case .none: return 0.0
                case .ambient: return 0.10
                case .attention: return 0.16
                case .urgent: return 0.24
                }
            }()
            let r1: CGFloat = {
                switch level {
                case .none: return 0
                case .ambient: return 16
                case .attention: return 14
                case .urgent: return 12
                }
            }()
            let r2: CGFloat = {
                switch level {
                case .none: return 0
                case .ambient: return 6
                case .attention: return 5
                case .urgent: return 4
                }
            }()
            content
                .shadow(color: PerchTheme.accent.opacity(alpha), radius: r1, x: 0, y: 0)
                .shadow(color: Color.black.opacity(0.30), radius: r2, x: 0, y: 2)
        }
    }
}

// MARK: - Reduce Motion Support

/// Environment-based reduce motion check.
/// Use `PerchMotion.prefersReduced` to skip non-essential animations.
enum PerchMotion {
    /// Returns `true` when the user has enabled Reduce Motion in system settings.
    static var prefersReduced: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    /// Returns the given animation when Reduce Motion is off, or `nil` (instant) when on.
    static func animation<A: Equatable>(_ animation: Animation, value: A) -> Animation? {
        prefersReduced ? nil : animation
    }

    /// Wraps `withAnimation` — uses instant transition when Reduce Motion is enabled.
    static func withOptionalAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
        if prefersReduced {
            return try body()
        } else {
            return try withAnimation(animation, body)
        }
    }
}

// MARK: - Card Prominence

/// Visual hierarchy levels for cards in the smart-ordered feed.
enum CardProminence {
    /// Active deliveries (out for delivery), imminent events (next 2h), daily brief
    case featured
    /// Default card style — most cards
    case standard
    /// Expired events, completed deliveries, old bookmarks
    case muted
}

// MARK: - View Extensions for Common Styling

extension View {
    /// Apply card styling with adaptive shadows.
    /// Tangerine cards: white surface on cool gray page + hairline border + soft neutral shadow.
    func cardStyle() -> some View {
        modifier(CardStyleModifier())
    }

    func perchGlow(_ level: PerchGlowLevel) -> some View {
        modifier(PerchGlowModifier(level: level))
    }

    /// Apply subtle border styling
    func cardBorder() -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                    .stroke(PerchTheme.border, lineWidth: 1)
            )
    }

    /// Staggered fade + slide-up card appear animation.
    /// Gentler spring (response 0.5, damping 0.85) — a touch softer and
    /// slower than before so cards arrive calmly rather than popping in.
    /// Skipped when Reduce Motion is on.
    func cardAppear(index: Int, appeared: Bool) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : (PerchMotion.prefersReduced ? 0 : 16))
            .animation(
                PerchMotion.prefersReduced
                    ? .none
                    : .spring(response: 0.5, dampingFraction: 0.85)
                        .delay(Double(index) * 0.05),
                value: appeared
            )
    }

    /// Urgency border overlay for stale data tiers
    func staleBorder(tier: UrgencyTier) -> some View {
        self.modifier(StaleBorderModifier(tier: tier))
    }

    /// Subtle scale on press for interactive cards (skipped when Reduce Motion is on)
    func cardTapScale(_ isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed && !PerchMotion.prefersReduced ? 0.97 : 1.0)
            .animation(
                PerchMotion.prefersReduced ? .none : .spring(response: 0.25, dampingFraction: 0.7),
                value: isPressed
            )
    }

    /// Apply visual prominence hierarchy to a card.
    func cardProminence(_ level: CardProminence) -> some View {
        modifier(CardProminenceModifier(level: level))
    }

    /// Hero card treatment: larger padding, accent top border, slightly larger title.
    /// Only the first card in the time-of-day stack should use this.
    func heroCard(ambientColor: Color) -> some View {
        modifier(HeroCardModifier(ambientColor: ambientColor))
    }
}

// MARK: - Adaptive Card Style Modifier

private struct CardStyleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    @Environment(\.perchPalette) private var palette

    func body(content: Content) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)

        // Palette-aware card fill — reads the active palette from the
        // environment so legacy `.cardStyle()` usages automatically tint
        // with the rest of the Today-feed system. No border, no shadow.
        content
            .background(cardShape.fill(palette.card))
    }
}

// MARK: - Haptic Feedback

enum PerchHaptics {
    /// Card tap, navigation, toggle collapse
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Pull-to-refresh start
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Picker change, segment switch, tab change
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Refresh complete, action succeeded, copy confirmed
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Error occurred
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

// MARK: - Animated Number Count-Up

struct AnimatedNumber: View {
    let value: Double
    let format: String
    var duration: Double = 0.6

    @State private var displayValue: Double = 0

    var body: some View {
        Text(String(format: format, displayValue))
            .onAppear {
                PerchMotion.withOptionalAnimation(.easeOut(duration: duration)) {
                    displayValue = value
                }
            }
            .onChange(of: value) { _, newValue in
                PerchMotion.withOptionalAnimation(.easeOut(duration: duration)) {
                    displayValue = newValue
                }
            }
    }
}

// MARK: - Interactive Card Button Style

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !PerchMotion.prefersReduced ? 0.97 : 1.0)
            .animation(
                PerchMotion.prefersReduced ? .none : .spring(response: 0.25, dampingFraction: 0.7),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    PerchHaptics.light()
                }
            }
    }
}

// MARK: - Stale Data Border Modifier

struct StaleBorderModifier: ViewModifier {
    let tier: UrgencyTier
    @State private var pulseOpacity: Double = 0.3

    func body(content: Content) -> some View {
        content
            .overlay(borderOverlay)
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch tier {
        case .fresh, .stale:
            EmptyView()
        case .warning:
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                .stroke(PerchTheme.accent.opacity(PerchMotion.prefersReduced ? 0.7 : pulseOpacity), lineWidth: 1.5)
                .shadow(color: PerchTheme.accent.opacity(0.18), radius: 10, x: 0, y: 0)
                .onAppear {
                    if !PerchMotion.prefersReduced { pulseOpacity = 0.7 }
                }
                .animation(
                    PerchMotion.prefersReduced
                        ? .none
                        : .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                    value: pulseOpacity
                )
        case .critical:
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                .stroke(PerchTheme.warning, lineWidth: 1.5)
                .shadow(color: PerchTheme.warning.opacity(0.20), radius: 10, x: 0, y: 0)
        }
    }
}

// MARK: - Card Prominence Modifier

private struct CardProminenceModifier: ViewModifier {
    let level: CardProminence
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        switch level {
        case .featured:
            content
                .overlay(
                    RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                        .stroke(PerchTheme.accent.opacity(0.35), lineWidth: 1.5)
                )
        case .standard:
            content
        case .muted:
            content
                .opacity(0.7)
        }
    }
}

// MARK: - Hero Card Modifier

private struct HeroCardModifier: ViewModifier {
    let ambientColor: Color

    func body(content: Content) -> some View {
        content
            .padding(.vertical, PerchTheme.Spacing.xSmall)
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [PerchTheme.steel.opacity(0.30), PerchTheme.accent.opacity(0.55)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 2)
                .clipShape(RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius))
            }
            .perchGlow(.ambient)
    }
}

// MARK: - PerchPhrase (Gentler interpretive phrase library)

/// Generates friendly interpretive phrases that sit alongside raw data on
/// Today cards. Each card defines buckets (e.g. "light day", "on track",
/// "over") and a library of phrasings per bucket. `PerchPhrase.today(...)`
/// returns a stable phrase for today that cycles through the library over
/// consecutive days so the dashboard never says the exact same thing twice
/// in a row — but never changes mid-day either.
///
/// Inspired by Gentler Streak's "translate data into words" approach —
/// statistics become a gentle read on how your day is shaping up.
///
/// Kept in this file (not a separate .swift) so it's picked up automatically
/// by the existing Xcode target membership for PerchTheme.
enum PerchPhrase {
    /// Returns a phrase from `library` keyed to today's date + a salt value.
    /// Matches Claude Design's `pickPhrase(arr, salt)`: `(doy + salt) % count`.
    /// Same day + same salt → same phrase; new day, same salt → next phrase
    /// in the rotation. `key` is kept as an additional spread factor so cards
    /// that share a bucket name but different semantics don't collide.
    static func today(_ library: [String], for key: String, salt: Int = 0) -> String {
        guard !library.isEmpty else { return "" }
        // Qualify as Foundation.Calendar — our nested `Calendar` enum
        // (holding calendar-card phrase libraries) shadows the type.
        let dayOfYear = Foundation.Calendar.current
            .ordinality(of: .day, in: .year, for: Date.now) ?? 0
        let keyHash = abs(key.perchStableHash)
        let index = abs(dayOfYear &+ salt &+ keyHash) % library.count
        return library[index]
    }

    // Card salts — keep these stable. Changing a salt rotates all that
    // card's phrases on day boundaries by one, so avoid unless intentional.
    // These match the Claude Design prototype salts.
    private enum Salt {
        static let calendar   = 1
        static let nutrition  = 2
        static let deliveries = 3
        static let health     = 4
        static let travel     = 5
        static let weather    = 6
        static let email      = 7
    }

    // MARK: Calendar

    enum Calendar {
        static let none = [
            "A breezy one", "Wide open", "Yours to shape",
            "Nothing scheduled", "All yours today", "Unwritten",
        ]
        static let light = [
            "Light calendar", "Room to breathe", "A gentle day ahead",
            "Two on the books", "An easy rhythm",
        ]
        static let medium = [
            "A few things on", "Steady schedule", "A handful of blocks",
            "A reasonable day", "Measured pace",
        ]
        static let heavy = [
            "Full plate", "Packed", "Back to back",
            "A lot on today", "Shoulder to the wheel",
        ]
    }

    static func calendarPhrase(eventCount: Int) -> String {
        let library: [String] = {
            if eventCount == 0 { return Calendar.none }
            if eventCount <= 2 { return Calendar.light }
            if eventCount <= 5 { return Calendar.medium }
            return Calendar.heavy
        }()
        return PerchPhrase.today(library, for: "cal", salt: Salt.calendar)
    }

    // MARK: Nutrition

    enum Nutrition {
        static let starting = [
            "Just getting started", "Plenty of room", "Early innings", "The day is young",
        ]
        static let light = [
            "Light day", "Easy pace", "Gentle fuel", "A modest one",
        ]
        static let on = [
            "On track", "Cruising", "Right in the pocket", "Settled in",
        ]
        static let spot = [
            "Right there", "Spot on", "Nailed it", "Dialed",
        ]
        static let more = [
            "A bigger day", "Hearty one", "Well-fed", "Generous portions",
        ]
    }

    static func nutritionPhrase(consumed: Double, target: Double) -> String {
        guard target > 0 else {
            return PerchPhrase.today(Nutrition.starting, for: "nut", salt: Salt.nutrition)
        }
        let ratio = consumed / target
        let library: [String] = {
            if ratio < 0.3 { return Nutrition.starting }
            if ratio < 0.7 { return Nutrition.light }
            if ratio < 1.0 { return Nutrition.on }
            if ratio < 1.1 { return Nutrition.spot }
            return Nutrition.more
        }()
        return PerchPhrase.today(library, for: "nut", salt: Salt.nutrition)
    }

    // MARK: Deliveries

    enum Delivery {
        static let none = [
            "Doorstep quiet", "Mailbox empty", "All clear",
            "Nothing inbound", "Quiet porch",
        ]
        static let one = [
            "One on the way", "A single delivery",
            "One parcel inbound", "Just the one",
        ]
        static let few = [
            "A couple on the way", "Handful in transit",
            "A few inbound", "Small cluster heading over",
        ]
        static let many = [
            "Busy doorstep", "Package parade",
            "Plenty inbound", "A flock of parcels",
        ]
    }

    static func deliveryPhrase(count: Int) -> String {
        let library: [String] = {
            if count == 0 { return Delivery.none }
            if count == 1 { return Delivery.one }
            if count <= 3 { return Delivery.few }
            return Delivery.many
        }()
        return PerchPhrase.today(library, for: "del", salt: Salt.deliveries)
    }

    // MARK: Health

    enum Health {
        static let low  = ["Running low", "A bit tired", "Take it easy", "Rest is the work"]
        static let mid  = ["Finding your feet", "Settling in", "Coming back around"]
        static let high = ["Well-rested", "Solid recovery", "Ready when you are", "Full tank"]
    }

    static func healthPhrase(recovery: Int) -> String {
        let library: [String] = {
            if recovery < 40 { return Health.low }
            if recovery < 70 { return Health.mid }
            return Health.high
        }()
        return PerchPhrase.today(library, for: "hlt", salt: Salt.health)
    }

    // MARK: Weather

    enum Weather {
        static let warm = ["A warm one, sunscreen if you\u{2019}re out", "Shoulders out weather", "Soft sun today"]
        static let mild = ["A light layer should do", "Pleasant all day", "Nothing to argue with"]
        static let cold = ["Bundle up", "A proper jumper day", "Cold hands, warm heart"]
        static let rain = ["Brollies out", "Wet feet likely", "A stay-inside kind of day"]
    }

    enum WeatherBucket { case warm, mild, cold, rain }

    static func weatherPhrase(bucket: WeatherBucket) -> String {
        let library: [String] = {
            switch bucket {
            case .warm: return Weather.warm
            case .mild: return Weather.mild
            case .cold: return Weather.cold
            case .rain: return Weather.rain
            }
        }()
        return PerchPhrase.today(library, for: "wx", salt: Salt.weather)
    }

    // MARK: Travel

    enum Travel {
        static let upcoming = ["Departure on the horizon", "The bags can wait, but only just", "Three sleeps away"]
        static let today    = ["Wheels up today", "Today\u{2019}s the day"]
        static let active   = ["On the road", "Away from the perch"]
    }

    enum TravelPhase { case upcoming, today, active }

    static func travelPhrase(phase: TravelPhase) -> String {
        let library: [String] = {
            switch phase {
            case .upcoming: return Travel.upcoming
            case .today:    return Travel.today
            case .active:   return Travel.active
            }
        }()
        return PerchPhrase.today(library, for: "trv", salt: Salt.travel)
    }

    // MARK: Email

    enum Email {
        static let none = ["Inbox at ease", "Quiet morning"]
        static let few  = ["A few worth a look", "A small pile", "Three threads worth a look"]
        static let many = ["Your inbox is awake", "A busy morning in there"]
    }

    static func emailPhrase(threadCount: Int) -> String {
        if threadCount > 0 {
            // The spec uses a literal count-driven phrase when there are
            // threads; library only applies to the empty state.
            return "\(threadCount) thread\(threadCount == 1 ? "" : "s") worth a look"
        }
        return PerchPhrase.today(Email.none, for: "em", salt: Salt.email)
    }

    // MARK: Meds

    /// Meds phrase is derived directly from taken/total (not library-rotated)
    /// because there are only three legible variants and the count is the
    /// meaningful signal.
    static func medsPhrase(taken: Int, total: Int) -> String {
        if total == 0      { return "A gentle reminder" }
        if taken == total  { return "All squared away" }
        if taken == 0      { return "A gentle reminder" }
        return "Steady as she goes"
    }
}

// Stable hashing — String.hashValue is randomised per launch on Apple
// platforms, so we hand-roll a djb2 hash to keep phrase rotation
// deterministic across app launches.
private extension String {
    var perchStableHash: Int {
        var hash: UInt64 = 5381
        for byte in utf8 { hash = ((hash << 5) &+ hash) &+ UInt64(byte) }
        return Int(truncatingIfNeeded: hash)
    }
}

// MARK: - PerchPalette (time-of-day token sets)

/// Full palette per time of day — the complete token set for every
/// visual decision on the Today feed. Matches the Claude Design
/// palette-change handoff verbatim.
///
/// Used in place of `PerchTheme.*` everywhere inside the Today tab so
/// the whole feed re-tints atomically with the hour. Other tabs still
/// read from PerchTheme for consistency.
///
/// Switch an entire palette at once — never mix-and-match tokens across
/// variants. Each palette is a complete coherent read.
struct PerchPalette: Equatable, Sendable {
    /// Page background (behind everything below the hero).
    let bg: Color
    /// Card body surface — one step lighter than bg.
    let card: Color
    /// Chip / retailer badge / search-bar / subtle-fill background.
    let chipBg: Color
    /// Divider, hairline, progress-bar track.
    let line: Color
    /// Primary ink colour.
    let ink: Color
    /// Secondary text — eyebrow labels, muted metadata.
    let muted: Color
    /// Tertiary text — freshness labels, inactive states.
    let faint: Color
    /// Kinetic accent — actions, time-sensitive signals, deliveries dot,
    /// high-priority email rail, travel eyebrow. Used as colour, NEVER
    /// as a large background (only 6pt dots, chips, bar fills).
    let kinetic: Color
    /// Wellness accent — nutrition ring, health eyebrows, "Now" chip,
    /// meds check, success. Same rules as kinetic.
    let wellness: Color
    /// The single highlight per surface (Stet 'marker'). Used ONLY by .perchMark — never as a fill.
    let marker: Color
    /// Hero scrim base — used in the V1 seam gradient at 0.15 alpha.
    /// Derived from the hero's dark tones for each time of day.
    /// NEVER use pure black — that kills the warm palette.
    let scrimDark: Color
    /// Error colour, in the same register as the palette.
    let error: Color
    /// Hero greeting text — ink-valued (same as `ink`).
    let heroText: Color

    // MARK: v2 extension tokens (Sections redesign)
    //
    // Subtler tones for cards-within-cards, soft dividers, and
    // semantic deltas (good / warn). `cardDim` sits between `card` and
    // `bg` so a sub-panel inside a card reads as tonally indented
    // without drawing a second border. `lineSoft` is a gentler hairline
    // for row separators inside the same card. `good` and `warn` are
    // ink-adjacent so they stay in the warm palette's register — no
    // pure red, no pure green.

    /// Subordinate panel fill inside a card (e.g. Travel flight strip).
    /// One step closer to `bg` than `card`. Always opaque.
    /// Stored — used to be computed and allocated 2 UIColor objects per
    /// access. Section/divider views read this dozens of times per
    /// render; the allocation churn was visible in profiles. Initialized
    /// in the custom init from card/bg via `Self.midpoint`.
    let cardDim: Color

    /// Soft divider inside a card (row separator). Lighter than `line`.
    /// Stored for the same reason as `cardDim`.
    let lineSoft: Color

    /// Custom init so the four `static let` palettes don't have to spell
    /// out cardDim/lineSoft — they get derived from card/bg/line once
    /// at module load.
    init(
        bg: Color, card: Color, chipBg: Color, line: Color,
        ink: Color, muted: Color, faint: Color,
        kinetic: Color, wellness: Color,
        marker: Color,
        scrimDark: Color, error: Color
    ) {
        self.bg = bg
        self.card = card
        self.chipBg = chipBg
        self.line = line
        self.ink = ink
        self.muted = muted
        self.faint = faint
        self.kinetic = kinetic
        self.wellness = wellness
        self.marker = marker
        self.scrimDark = scrimDark
        self.error = error
        self.heroText = ink
        self.cardDim = Self.midpoint(card, bg, t: 0.35)
        self.lineSoft = Self.midpoint(card, line, t: 0.6)
    }

    /// Positive delta (e.g. +22m, +4%). Moss green, ink-adjacent.
    let good: Color = Color(red: 0.420, green: 0.561, blue: 0.369) // #6B8F5E

    /// Warning (watchouts). Amber, never red.
    let warn: Color = Color(red: 0.769, green: 0.541, blue: 0.247) // #C48A3F

    /// Linear RGB midpoint helper for deriving tonal tokens.
    /// `t` = 0 returns a, `t` = 1 returns b. Uses UIColor for RGB
    /// extraction so results match design specs closely.
    private static func midpoint(_ a: Color, _ b: Color, t: CGFloat) -> Color {
        let ua = UIColor(a)
        let ub = UIColor(b)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ua.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        ub.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(
            red:   Double(ar + (br - ar) * t),
            green: Double(ag + (bg - ag) * t),
            blue:  Double(ab + (bb - ab) * t)
        )
    }

    // MARK: Palette library

    /// Morning — pale warm cream-peach. 05:00–10:59.
    static let sunrise = PerchPalette(
        bg:        Color(hex: 0xF8E7D2),
        card:      Color(hex: 0xFCF2E2),
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
    /// Afternoon (HERO) — warm peach-pink. 11:00–16:59.
    static let midday = PerchPalette(
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
    /// Evening — dusty rose-clay; plum-magenta kinetic earns its place here. 17:00–21:59.
    static let dusk = PerchPalette(
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
    /// Night — deep indigo (true dark, color-scheme: dark), cream ink. 22:00–04:59.
    static let night = PerchPalette(
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

    /// Pick the palette for the given time-of-day.
    static func forTimeOfDay(_ t: PerchTimeOfDay) -> PerchPalette {
        switch t {
        case .sunrise: return .sunrise
        case .midday:  return .midday
        case .dusk:    return .dusk
        case .night:   return .night
        }
    }
}

// MARK: - PerchTimeOfDay

/// Time-of-day bracket used to select the active palette.
/// Kept here (not in TodayTab) so other views can participate.
enum PerchTimeOfDay: Sendable {
    case sunrise, midday, dusk, night

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

    var colorScheme: ColorScheme { self == .night ? .dark : .light }

    var heroImageName: String {
        switch self {
        case .sunrise: return "hero-morning"
        case .midday:  return "hero-afternoon"
        case .dusk:    return "hero-evening"
        case .night:   return "hero-night"
        }
    }

    var heroVideoName: String? {
        switch self {
        case .sunrise: return "hero-morning-video"
        case .midday:  return "hero-afternoon-video"
        case .dusk:    return "hero-evening-video"
        case .night:   return "hero-night-video"
        }
    }

    /// Greeting copy per the Claude Design handoff. The night variant
    /// is deliberately question-tagged. The trailing `, name` is
    /// appended at the call site from `public.users.display_name`,
    /// falling back to no-name greetings ("Good morning.") when no
    /// display name has been set yet.
    var greetingPrefix: String {
        switch self {
        case .sunrise: return "Good morning"
        case .midday:  return "Afternoon"
        case .dusk:    return "Evening"
        case .night:   return "Still up"
        }
    }

    /// Whether this greeting should end with a question mark when a
    /// name is appended ("Still up, Alex?") vs a period ("Good morning,
    /// Alex.").
    var greetingIsQuestion: Bool {
        self == .night
    }

    /// Format the greeting with an optional display name. Pass nil/empty
    /// to render without a name ("Good morning." / "Still up?").
    func greeting(name: String?) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suffix = greetingIsQuestion ? "?" : "."
        if trimmed.isEmpty {
            return "\(greetingPrefix)\(suffix)"
        }
        return "\(greetingPrefix), \(trimmed)\(suffix)"
    }

    var accessibilityLabel: String {
        switch self {
        case .sunrise: return "Sunrise scene"
        case .midday:  return "Midday scene"
        case .dusk:    return "Dusk scene"
        case .night:   return "Night scene"
        }
    }
}

// MARK: - Color(hex:) convenience

extension Color {
    /// 0xRRGGBB → opaque sRGB Color. Used by the locked time-of-day palettes.
    init(hex: UInt) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Environment plumbing

private struct PerchPaletteKey: EnvironmentKey {
    static let defaultValue: PerchPalette = .midday
}

private struct PerchTimeOfDayKey: EnvironmentKey {
    static let defaultValue: PerchTimeOfDay = .midday
}

extension EnvironmentValues {
    /// The active palette for the current view hierarchy. Today-feed
    /// primitives (TodayCard / TodayEyebrow / TodayPhrase / TodaySearchBar /
    /// TodayChip) read this for every colour they render.
    var perchPalette: PerchPalette {
        get { self[PerchPaletteKey.self] }
        set { self[PerchPaletteKey.self] = newValue }
    }

    /// Time-of-day bracket corresponding to `perchPalette`. Rarely read
    /// directly — most code wants `perchPalette` — but useful for
    /// hero-image / greeting / scrim selection.
    var perchTimeOfDay: PerchTimeOfDay {
        get { self[PerchTimeOfDayKey.self] }
        set { self[PerchTimeOfDayKey.self] = newValue }
    }
}
