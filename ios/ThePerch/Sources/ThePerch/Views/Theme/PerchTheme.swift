import SwiftUI

/// Centralized theme configuration for The Perch app.
/// "Gentler Perch" — warm editorial aesthetic inspired by Gentler Streak's
/// soft, encouraging tone. Cream (#F7F3EC) page behind soft-warm cards,
/// stone-palette text (warm neutrals, not cold zinc), 20pt radii so cards
/// feel plush, dual-accent vocabulary: tangerine (#E05D38) for kinetic
/// signal (actions, alerts, travel, deliveries) and sage (#7A9E7C) for
/// wellness signal (nutrition, health, sleep, workouts). Data paired with
/// rotating interpretive phrases — "Light day" instead of just "489 kcal".
/// Dark mode on stone-950 / stone-900 preserving the warmth.
struct PerchTheme {
    // MARK: - Adaptive Color Helper

    /// Creates a Color that adapts between dark and light mode.
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    // MARK: - Colors (Tangerine palette — OKLCH → sRGB)

    /// Page background — cream/linen (light) / stone-950 (dark).
    /// Warm neutrals that read as "paper" instead of "screen". The #F7F3EC
    /// cream gives a softer canvas than cool off-whites, and preserves
    /// depth against the soft-warm card surfaces without any border chrome.
    static var background: Color {
        adaptive(
            light: UIColor(red: 0.969, green: 0.953, blue: 0.925, alpha: 1),  // #F7F3EC (linen)
            dark:  UIColor(red: 0.043, green: 0.039, blue: 0.035, alpha: 1)   // #0B0A09 (stone-950)
        )
    }

    /// Elevated surface for cards — soft warm white (light) / stone-900 (dark).
    /// Not quite pure white — #FEFCF8 has the barest cream undertone so cards
    /// feel part of the same warm world as the background, not sterile islands.
    static var cardBackground: Color {
        adaptive(
            light: UIColor(red: 0.996, green: 0.988, blue: 0.973, alpha: 1),  // #FEFCF8 (soft warm white)
            dark:  UIColor(red: 0.110, green: 0.098, blue: 0.094, alpha: 1)   // #1C1918 (stone-900)
        )
    }

    /// Inner surface for items within cards — barely-lifted warm neutral
    /// in light, one notch up in dark.
    static var cardInnerBackground: Color {
        adaptive(
            light: UIColor(red: 0.953, green: 0.941, blue: 0.922, alpha: 1),  // #F3F0EB (warm stone-100)
            dark:  UIColor(red: 0.161, green: 0.145, blue: 0.137, alpha: 1)   // #292523 (stone-800)
        )
    }

    /// Card hover/pressed state — one step deeper than cardInner.
    static var cardHover: Color {
        adaptive(
            light: UIColor(red: 0.906, green: 0.890, blue: 0.867, alpha: 1),  // #E7E3DD
            dark:  UIColor(red: 0.235, green: 0.216, blue: 0.208, alpha: 1)   // #3C3735
        )
    }

    /// Primary text — warm near-black (light) / cream-white (dark).
    /// Stone-900 instead of pure black gives a softer, "ink-on-paper" feel.
    static var textPrimary: Color {
        adaptive(
            light: UIColor(red: 0.110, green: 0.098, blue: 0.090, alpha: 1),  // #1C1917 (stone-900)
            dark:  UIColor(red: 0.969, green: 0.961, blue: 0.949, alpha: 1)   // #F7F5F2 (warm white)
        )
    }

    /// Secondary text — warm stone-500 light / stone-400 dark.
    /// Meets WCAG AA on card surfaces in both modes.
    static var textSecondary: Color {
        adaptive(
            light: UIColor(red: 0.471, green: 0.443, blue: 0.420, alpha: 1),  // #78716C (stone-500)
            dark:  UIColor(red: 0.659, green: 0.635, blue: 0.608, alpha: 1)   // #A8A29E (stone-400)
        )
    }

    /// Tertiary text — stone-400 light / stone-500 dark. Timestamps, helpers.
    static var textTertiary: Color {
        adaptive(
            light: UIColor(red: 0.659, green: 0.635, blue: 0.608, alpha: 1),  // #A8A29E (stone-400)
            dark:  UIColor(red: 0.471, green: 0.443, blue: 0.420, alpha: 1)   // #78716C (stone-500)
        )
    }

    /// Accent — tangerine orange. Gentler Perch reserves tangerine for
    /// KINETIC signal: actions, alerts, travel, deliveries, the "something
    /// is happening" energy. Wellness cards (nutrition, health, sleep) use
    /// `wellness` (sage green) instead so the feed doesn't shout in one color.
    static var accent: Color {
        adaptive(
            light: UIColor(red: 0.878, green: 0.365, blue: 0.220, alpha: 1),  // #E05D38
            dark:  UIColor(red: 1.000, green: 0.439, blue: 0.251, alpha: 1)   // #FF7040
        )
    }

    /// Wellness accent — soft sage green. Used for nutrition, health summary,
    /// sleep/recovery, workouts — anything body-related. Calmer than the
    /// tangerine so the dashboard has two distinct emotional registers:
    /// "do/go" (tangerine) and "notice/restore" (sage).
    static var wellness: Color {
        adaptive(
            light: UIColor(red: 0.478, green: 0.620, blue: 0.486, alpha: 1),  // #7A9E7C (soft sage)
            dark:  UIColor(red: 0.588, green: 0.737, blue: 0.592, alpha: 1)   // #96BC97 (brighter sage for dark bg)
        )
    }

    /// Soft wellness tint for backgrounds of "at target / success" states.
    static var wellnessMuted: Color {
        adaptive(
            light: UIColor(red: 0.478, green: 0.620, blue: 0.486, alpha: 0.12),
            dark:  UIColor(red: 0.588, green: 0.737, blue: 0.592, alpha: 0.18)
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

    /// Error — warm terracotta instead of alarm red. Still clearly signals
    /// "something's off" but in the same warm register as the rest of the
    /// palette, so it doesn't break the calm when it appears.
    static var error: Color {
        adaptive(
            light: UIColor(red: 0.722, green: 0.290, blue: 0.231, alpha: 1),  // #B84A3B (terracotta)
            dark:  UIColor(red: 0.847, green: 0.478, blue: 0.412, alpha: 1)   // #D87A69 (lighter terracotta)
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

    /// Border — warm stone hairline, only used for inner dividers now.
    /// The main card style no longer uses borders (depth from tonal contrast).
    static var border: Color {
        adaptive(
            light: UIColor(red: 0.906, green: 0.890, blue: 0.867, alpha: 1),  // #E7E3DD (warm stone-200)
            dark:  UIColor(red: 0.161, green: 0.145, blue: 0.137, alpha: 1)   // #292523 (stone-800)
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

    // MARK: - Typography (SF Pro — editorial scale with strong hierarchy)

    enum Font {
        /// 40pt — hero numbers (calorie counts, event counts)
        static let largeTitle = SwiftUI.Font.system(size: 40, weight: .bold, design: .default)
        /// 40pt — alias for largeTitle; use .displayNumeric for monospaced hero numbers
        static let display = SwiftUI.Font.system(size: 40, weight: .bold, design: .default)
        /// 28pt — page / tab titles (Good afternoon, section headers)
        static let title = SwiftUI.Font.system(size: 28, weight: .semibold, design: .default)
        /// 17pt — card titles, emphasised data
        static let heading = SwiftUI.Font.system(size: 17, weight: .semibold, design: .default)
        /// 15pt — regular text, event titles, row values
        static let body = SwiftUI.Font.system(size: 15, weight: .regular, design: .default)
        /// 13pt — metadata, labels, freshness timestamps
        static let caption = SwiftUI.Font.system(size: 13, weight: .regular, design: .default)
        /// 11pt — footnotes, inline timestamps
        static let micro = SwiftUI.Font.system(size: 11, weight: .regular, design: .default)
        /// 11pt — uppercase section eyebrows (apply `.tracking(1.0).textCase(.uppercase)`)
        static let cardEyebrow = SwiftUI.Font.system(size: 11, weight: .semibold, design: .default)

        // Numeric variants — monospaced for aligned columns (times, macros, metrics).
        // Use .displayNumeric for hero stats (big calorie count, day totals).
        static let largeTitleNumeric = SwiftUI.Font.system(size: 40, weight: .bold,     design: .monospaced)
        static let displayNumeric    = SwiftUI.Font.system(size: 40, weight: .bold,     design: .monospaced)
        static let titleNumeric      = SwiftUI.Font.system(size: 28, weight: .semibold, design: .monospaced)
        static let headingNumeric    = SwiftUI.Font.system(size: 17, weight: .semibold, design: .monospaced)
        static let bodyNumeric       = SwiftUI.Font.system(size: 15, weight: .medium,   design: .monospaced)
        static let captionNumeric    = SwiftUI.Font.system(size: 13, weight: .medium,   design: .monospaced)
        static let microNumeric      = SwiftUI.Font.system(size: 11, weight: .medium,   design: .monospaced)

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

        /// Vertical rhythm between stacked cards in the Today/Health feeds.
        /// Editorial spacing replaces the old border-separated rhythm — tune
        /// whitespace, not chrome, to create hierarchy. 20pt sits in the
        /// sweet spot where cards still feel grouped as a feed, not floating
        /// islands.
        static let cardStack: CGFloat = 20
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
        EmptyView() // Placeholder; actual implementation in GlassTabBar.swift
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

    func body(content: Content) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)

        // Editorial card: no border, no light-mode drop shadow.
        // Depth in light mode comes purely from the tonal contrast of pure
        // white on the warm-off-white page background. Dark mode keeps a
        // whisper of shadow because zinc-900 on zinc-950 alone is too flat.
        content
            .background(cardShape.fill(PerchTheme.cardBackground))
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.0),
                radius: colorScheme == .dark ? 10 : 0,
                x: 0,
                y: colorScheme == .dark ? 4 : 0
            )
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
    /// Returns a phrase from `library` keyed to today's date combined with
    /// `key`. Same calendar day + same key → same phrase. New day, same
    /// key → next phrase in the rotation. Different key → different hash
    /// offset so two cards on the same day don't land on the same phrase
    /// by accident.
    static func today(_ library: [String], for key: String) -> String {
        guard !library.isEmpty else { return "" }
        // Qualify as Foundation.Calendar — our nested `Calendar` enum
        // (holding calendar-card phrase libraries) shadows the type.
        let dayOfYear = Foundation.Calendar.current
            .ordinality(of: .day, in: .year, for: Date.now) ?? 0
        let keyHash = abs(key.perchStableHash)
        let index = (dayOfYear &+ keyHash) % library.count
        return library[index]
    }

    // MARK: Nutrition libraries

    enum Nutrition {
        /// < 30% of target — plenty of runway left.
        static let low = [
            "Just getting started", "Plenty of room", "Early innings",
            "Quiet start", "Fresh canvas", "Barely begun",
        ]
        /// 30–70% of target — a light day so far.
        static let light = [
            "Light day", "Easy pace", "Steady mode",
            "Half-full", "Moderate fuel", "Gentle rhythm",
        ]
        /// 70–100% of target — cruising toward it.
        static let onTrack = [
            "On track", "Cruising", "Nicely paced",
            "Good rhythm", "Right on", "Within reach",
        ]
        /// 100–110% of target — landed right around the mark.
        static let onTarget = [
            "Right there", "Spot on", "Basically at target",
            "Bullseye", "Met it", "Landed it",
        ]
        /// > 110% of target — gone past for the day.
        static let over = [
            "A bigger day", "Past the line", "Hearty one",
            "Over for today", "Generous", "Abundant",
        ]
    }

    static func nutritionPhrase(consumed: Double, target: Double) -> String {
        guard target > 0 else {
            return PerchPhrase.today(Nutrition.low, for: "nutrition-low")
        }
        let ratio = consumed / target
        let (library, bucket): ([String], String) = {
            if ratio < 0.3  { return (Nutrition.low,      "nutrition-low") }
            if ratio < 0.7  { return (Nutrition.light,    "nutrition-light") }
            if ratio < 1.0  { return (Nutrition.onTrack,  "nutrition-ontrack") }
            if ratio <= 1.1 { return (Nutrition.onTarget, "nutrition-ontarget") }
            return (Nutrition.over, "nutrition-over")
        }()
        return PerchPhrase.today(library, for: bucket)
    }

    // MARK: Calendar libraries

    enum Calendar {
        static let empty = [
            "A breezy one", "Wide open", "Nothing scheduled",
            "Empty canvas", "Free range", "Open skies", "Yours to shape",
        ]
        static let light = [
            "Light calendar", "Easy day", "A touch to do",
            "Manageable", "Room to breathe", "Quiet-ish",
        ]
        static let steady = [
            "A few things on", "Steady schedule", "Solid plate",
            "Active day", "Nicely filled", "Busy-ish",
        ]
        static let full = [
            "Full plate", "Packed", "Back to back",
            "Busy one", "Juggling act", "A lot going on",
        ]
    }

    static func calendarPhrase(eventCount: Int) -> String {
        let (library, bucket): ([String], String) = {
            if eventCount == 0 { return (Calendar.empty,  "cal-empty") }
            if eventCount <= 2 { return (Calendar.light,  "cal-light") }
            if eventCount <= 5 { return (Calendar.steady, "cal-steady") }
            return (Calendar.full, "cal-full")
        }()
        return PerchPhrase.today(library, for: bucket)
    }

    // MARK: Delivery libraries

    enum Delivery {
        static let empty = [
            "Nothing in transit", "Doorstep quiet", "All clear",
            "No packages today", "Mailbox empty",
        ]
        static let one = [
            "One on the way", "A single delivery",
            "One in flight", "One inbound",
        ]
        static let few = [
            "A couple on the way", "Few incoming",
            "Handful in transit", "Trickle of boxes",
        ]
        static let many = [
            "Busy doorstep", "Lots incoming",
            "Package parade", "Mailbox working overtime",
        ]
    }

    static func deliveryPhrase(count: Int) -> String {
        let (library, bucket): ([String], String) = {
            if count == 0 { return (Delivery.empty, "del-empty") }
            if count == 1 { return (Delivery.one,   "del-one") }
            if count <= 3 { return (Delivery.few,   "del-few") }
            return (Delivery.many, "del-many")
        }()
        return PerchPhrase.today(library, for: bucket)
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
