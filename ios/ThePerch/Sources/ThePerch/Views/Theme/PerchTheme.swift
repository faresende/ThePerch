import SwiftUI

/// Centralized theme configuration for The Perch app.
/// "Quiet Dashboard" — editorial aesthetic with content-first surfaces.
/// Inspired by Things 3 / Craft / Linear: no borders, no light-mode shadows,
/// warm off-white (#FAFAF9) page behind pure-white cards, 16pt radii,
/// strong typographic hierarchy (40pt display numerics, 11pt uppercase
/// eyebrows), tangerine accent (#E05D38) used sparingly for the single
/// highest-signal value per card.
/// Dark mode mirrors the same structure on zinc-950 / zinc-900 surfaces.
struct PerchTheme {
    // MARK: - Adaptive Color Helper

    /// Creates a Color that adapts between dark and light mode.
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    // MARK: - Colors (Tangerine palette — OKLCH → sRGB)

    /// Page background — warm off-white (light) / zinc-950 (dark).
    /// The warmth at ~#FAFAF9 gives depth against pure-white cards without
    /// needing borders or shadows to separate them.
    static var background: Color {
        adaptive(
            light: UIColor(red: 0.980, green: 0.980, blue: 0.976, alpha: 1),  // #FAFAF9
            dark:  UIColor(red: 0.035, green: 0.035, blue: 0.043, alpha: 1)   // #09090B (zinc-950)
        )
    }

    /// Elevated surface for cards — pure white (light) / zinc-900 (dark).
    /// Depth comes from tonal contrast vs the slightly-warmer background,
    /// not from borders or drop shadows.
    static var cardBackground: Color {
        adaptive(
            light: UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1),  // #FFFFFF
            dark:  UIColor(red: 0.094, green: 0.094, blue: 0.106, alpha: 1)   // #18181B (zinc-900)
        )
    }

    /// Inner surface for items within cards (selected rows, selectors) —
    /// barely there in light, one notch lifted in dark.
    static var cardInnerBackground: Color {
        adaptive(
            light: UIColor(red: 0.961, green: 0.961, blue: 0.961, alpha: 1),  // #F5F5F5 (zinc-100)
            dark:  UIColor(red: 0.149, green: 0.149, blue: 0.161, alpha: 1)   // #27272A (zinc-800)
        )
    }

    /// Card hover/pressed state — one step deeper than cardInner.
    static var cardHover: Color {
        adaptive(
            light: UIColor(red: 0.910, green: 0.910, blue: 0.914, alpha: 1),  // #E8E8E9
            dark:  UIColor(red: 0.227, green: 0.227, blue: 0.239, alpha: 1)   // #3A3A3C
        )
    }

    /// Primary text — near-black (light) / near-white (dark).
    /// Uses #0F0F0F / #FAFAFA instead of pure black/white for reduced
    /// harshness at display sizes.
    static var textPrimary: Color {
        adaptive(
            light: UIColor(red: 0.059, green: 0.059, blue: 0.059, alpha: 1),  // #0F0F0F
            dark:  UIColor(red: 0.980, green: 0.980, blue: 0.980, alpha: 1)   // #FAFAFA
        )
    }

    /// Secondary text — zinc-500 light / zinc-400 dark.
    /// Meets WCAG AA on card surfaces in both modes.
    static var textSecondary: Color {
        adaptive(
            light: UIColor(red: 0.443, green: 0.443, blue: 0.478, alpha: 1),  // #71717A (zinc-500)
            dark:  UIColor(red: 0.631, green: 0.631, blue: 0.667, alpha: 1)   // #A1A1AA (zinc-400)
        )
    }

    /// Tertiary text — zinc-400 light / zinc-500 dark. For timestamps,
    /// helper text, and auxiliary metadata.
    static var textTertiary: Color {
        adaptive(
            light: UIColor(red: 0.631, green: 0.631, blue: 0.667, alpha: 1),  // #A1A1AA (zinc-400)
            dark:  UIColor(red: 0.443, green: 0.443, blue: 0.478, alpha: 1)   // #71717A (zinc-500)
        )
    }

    /// Accent — tangerine orange (the theme's `primary`)
    /// Light: oklch(0.6397 0.1720 36.44) → #E05D38
    /// Dark: slightly brighter for contrast on charcoal → #FF7040
    static var accent: Color {
        adaptive(
            light: UIColor(red: 0.878, green: 0.365, blue: 0.220, alpha: 1),  // #E05D38
            dark:  UIColor(red: 1.000, green: 0.439, blue: 0.251, alpha: 1)   // #FF7040
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

    /// Success — clean green
    static var success: Color {
        adaptive(
            light: UIColor(red: 0.086, green: 0.639, blue: 0.290, alpha: 1),  // #16A34A
            dark:  UIColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1)   // #34C759
        )
    }

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

    /// Error — red (the theme's `destructive`)
    /// Light: oklch(0.6368 0.2078 25.33) → #DC2626
    static var error: Color {
        adaptive(
            light: UIColor(red: 0.863, green: 0.149, blue: 0.149, alpha: 1),  // #DC2626
            dark:  UIColor(red: 1.000, green: 0.271, blue: 0.227, alpha: 1)   // #FF453A
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

    /// Border — barely-there hairline, only used for inner dividers now.
    /// The main card style no longer uses borders (depth from tonal contrast).
    static var border: Color {
        adaptive(
            light: UIColor(red: 0.894, green: 0.894, blue: 0.906, alpha: 1),  // #E4E4E7 (zinc-200)
            dark:  UIColor(red: 0.149, green: 0.149, blue: 0.161, alpha: 1)   // #27272A (zinc-800)
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

    // MARK: - Card Styling (editorial — no border, no light-mode shadow)

    enum Card {
        static let cornerRadius: CGFloat = 16
        static let innerCornerRadius: CGFloat = 10
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

    /// Staggered fade + slide-up card appear animation (skipped when Reduce Motion is on)
    func cardAppear(index: Int, appeared: Bool) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : (PerchMotion.prefersReduced ? 0 : 20))
            .animation(
                PerchMotion.prefersReduced
                    ? .none
                    : .spring(response: 0.45, dampingFraction: 0.8)
                        .delay(Double(index) * 0.06),
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
