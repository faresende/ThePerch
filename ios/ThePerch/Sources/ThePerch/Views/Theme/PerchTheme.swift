import SwiftUI

/// Centralized theme configuration for The Perch app.
/// Adaptive dark/light theme with warm amber accent.
/// Dark mode: near-black with ambient glow. Light mode: warm white with neutral shadows.
struct PerchTheme {
    // MARK: - Adaptive Color Helper

    /// Creates a Color that adapts between dark and light mode.
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    // MARK: - Colors

    /// Main background — near black (dark) / warm white (light)
    static var background: Color {
        adaptive(
            light: UIColor(red: 0.973, green: 0.969, blue: 0.961, alpha: 1),  // #F8F7F5
            dark: UIColor(red: 0.071, green: 0.071, blue: 0.075, alpha: 1)    // #121213
        )
    }

    /// Elevated surface for cards
    static var cardBackground: Color {
        adaptive(
            light: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),        // #FFFFFF
            dark: UIColor(red: 0.098, green: 0.102, blue: 0.106, alpha: 1)    // #191A1B
        )
    }

    /// Inner surface for items within cards (checklist rows, selectors)
    static var cardInnerBackground: Color {
        adaptive(
            light: UIColor(red: 0.949, green: 0.945, blue: 0.937, alpha: 1),  // #F2F1EF
            dark: UIColor(red: 0.129, green: 0.133, blue: 0.145, alpha: 1)    // #212225
        )
    }

    /// Card hover/pressed state
    static var cardHover: Color {
        adaptive(
            light: UIColor(red: 0.929, green: 0.925, blue: 0.918, alpha: 1),  // #EDECEB
            dark: UIColor(red: 0.149, green: 0.153, blue: 0.169, alpha: 1)    // #26272B
        )
    }

    /// Primary text — near white (dark) / near black (light)
    static var textPrimary: Color {
        adaptive(
            light: UIColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1),  // #1A1A1A
            dark: UIColor(red: 0.949, green: 0.941, blue: 0.922, alpha: 1)    // #F2F0EB
        )
    }

    /// Secondary text — neutral gray (WCAG AA compliant, ≥4.5:1 on cards)
    static var textSecondary: Color {
        adaptive(
            light: UIColor(red: 0.420, green: 0.420, blue: 0.440, alpha: 1),  // #6B6B70
            dark: UIColor(red: 0.635, green: 0.616, blue: 0.584, alpha: 1)    // #A29D95
        )
    }

    /// Tertiary text — dim (WCAG AA compliant, ≥4.5:1 on background)
    static var textTertiary: Color {
        adaptive(
            light: UIColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1),  // #8E8E93
            dark: UIColor(red: 0.490, green: 0.471, blue: 0.443, alpha: 1)    // #7D7871
        )
    }

    /// Accent — warm amber/gold, slightly deeper in light mode for contrast
    static var accent: Color {
        adaptive(
            light: UIColor(red: 0.784, green: 0.518, blue: 0.039, alpha: 1),  // #C8840A
            dark: UIColor(red: 0.949, green: 0.690, blue: 0.290, alpha: 1)    // #F2B04A
        )
    }

    /// Text color for use on accent-colored backgrounds (WCAG AA ≥4.5:1)
    static var accentForeground: Color {
        adaptive(
            light: UIColor(red: 0.15, green: 0.10, blue: 0.0, alpha: 1),     // #261A00 — dark brown
            dark: UIColor(red: 0.102, green: 0.071, blue: 0.024, alpha: 1)   // #1A1206 — near-black warm
        )
    }

    /// Muted accent for tinted backgrounds
    static var accentMuted: Color {
        adaptive(
            light: UIColor(red: 0.831, green: 0.580, blue: 0.051, alpha: 0.10),
            dark: UIColor(red: 0.96, green: 0.68, blue: 0.15, alpha: 0.15)
        )
    }

    /// Accent glow — amber glow in dark mode, transparent in light mode
    static var accentGlow: Color {
        adaptive(
            light: UIColor(red: 0, green: 0, blue: 0, alpha: 0),              // transparent
            dark: UIColor(red: 0.949, green: 0.690, blue: 0.290, alpha: 0.14) // amber glow
        )
    }

    /// Success — slightly deeper in light mode
    static var success: Color {
        adaptive(
            light: UIColor(red: 0.114, green: 0.541, blue: 0.235, alpha: 1),  // #1D8A3C
            dark: UIColor(red: 0.220, green: 0.788, blue: 0.478, alpha: 1)    // #38C97A
        )
    }

    /// Warning — warm orange, visually distinct from accent amber
    static var warning: Color {
        adaptive(
            light: UIColor(red: 0.769, green: 0.498, blue: 0.039, alpha: 1),  // #C47F0A
            dark: UIColor(red: 0.941, green: 0.635, blue: 0.290, alpha: 1)    // #F0A24A
        )
    }

    /// Subtle warning background tint
    static var warningBackground: Color {
        adaptive(
            light: UIColor(red: 0.922, green: 0.600, blue: 0.149, alpha: 0.10),
            dark: UIColor(red: 0.922, green: 0.600, blue: 0.149, alpha: 0.15)
        )
    }

    /// Error — slightly deeper in light mode
    static var error: Color {
        adaptive(
            light: UIColor(red: 0.769, green: 0.169, blue: 0.169, alpha: 1),  // #C42B2B
            dark: UIColor(red: 0.910, green: 0.353, blue: 0.353, alpha: 1)    // #E85A5A
        )
    }

    /// Semantic macro colors — shared across Home and Health nutrition cards.
    static var macroProtein: Color { success }
    static var macroCarbs: Color { accent }
    static var macroFat: Color { warning }

    static var macroProteinGradient: [Color] {
        [macroProtein.opacity(0.72), macroProtein]
    }

    static var macroCarbsGradient: [Color] {
        [macroCarbs.opacity(0.72), macroCarbs]
    }

    static var macroFatGradient: [Color] {
        [macroFat.opacity(0.72), macroFat]
    }

    /// Border — subtle, neutral
    static var border: Color {
        adaptive(
            light: UIColor(red: 0.847, green: 0.839, blue: 0.827, alpha: 1),  // #D8D6D3
            dark: UIColor(red: 0.173, green: 0.180, blue: 0.200, alpha: 1)    // #2C2E33
        )
    }

    /// Secondary accent — cool steel gray from icon tips
    static var steel: Color {
        adaptive(
            light: UIColor(red: 0.357, green: 0.380, blue: 0.420, alpha: 1),  // #5B616B
            dark: UIColor(red: 0.655, green: 0.678, blue: 0.714, alpha: 1)    // #A7ADB6
        )
    }

    /// Low-contrast steel tint for dividers and subtle iconography
    static var steelMuted: Color {
        adaptive(
            light: UIColor(red: 0.357, green: 0.380, blue: 0.420, alpha: 0.10),
            dark: UIColor(red: 0.655, green: 0.678, blue: 0.714, alpha: 0.16)
        )
    }

    /// Hairline dividers (especially inside cards)
    static var divider: Color {
        adaptive(
            light: UIColor(red: 0.898, green: 0.882, blue: 0.859, alpha: 1),  // #E5E1DB
            dark: UIColor(red: 0.165, green: 0.169, blue: 0.184, alpha: 1)    // #2A2B2F
        )
    }

    /// Focus ring for selected controls (dark mode only)
    static var focusRing: Color {
        adaptive(
            light: UIColor(red: 0, green: 0, blue: 0, alpha: 0),
            dark: UIColor(red: 0.949, green: 0.690, blue: 0.290, alpha: 0.28)
        )
    }

    // MARK: - Typography

    enum Font {
        /// 32pt — large hero numbers, page titles
        static let display = SwiftUI.Font.system(size: 32, weight: .bold)
        /// 22pt — section titles
        static let title = SwiftUI.Font.system(size: 22, weight: .semibold)
        /// 17pt — card titles, emphasis
        static let heading = SwiftUI.Font.system(size: 17, weight: .semibold)
        /// 15pt — regular text
        static let body = SwiftUI.Font.system(size: 15, weight: .regular)
        /// 13pt — metadata, labels
        static let caption = SwiftUI.Font.system(size: 13, weight: .regular)
        /// 11pt — footnotes, timestamps
        static let micro = SwiftUI.Font.system(size: 11, weight: .regular)
        /// 12pt — uppercase card section labels
        static let cardEyebrow = SwiftUI.Font.system(size: 12, weight: .semibold)

        // Numeric variants — .rounded design for data displays
        static let displayNumeric = SwiftUI.Font.system(size: 32, weight: .bold, design: .rounded)
        static let titleNumeric = SwiftUI.Font.system(size: 22, weight: .bold, design: .rounded)
        static let headingNumeric = SwiftUI.Font.system(size: 17, weight: .bold, design: .rounded)
        static let bodyNumeric = SwiftUI.Font.system(size: 15, weight: .semibold, design: .rounded)
        static let captionNumeric = SwiftUI.Font.system(size: 13, weight: .semibold, design: .rounded)
        static let microNumeric = SwiftUI.Font.system(size: 11, weight: .semibold, design: .rounded)

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
        static let xxxSmall: CGFloat = 2
        static let xxSmall: CGFloat = 4
        static let xSmall: CGFloat = 8
        static let small: CGFloat = 12
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
        static let xxLarge: CGFloat = 48
    }

    // MARK: - Card Styling

    enum Card {
        static let cornerRadius: CGFloat = 18
        static let innerCornerRadius: CGFloat = 12
        static let padding: CGFloat = 20
        static let shadowRadius: CGFloat = 12
        static let shadowOpacity: Double = 0.4
        static let borderWidth: CGFloat = 1
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
                case .ambient: return 0.14
                case .attention: return 0.22
                case .urgent: return 0.34
                }
            }()
            let r1: CGFloat = {
                switch level {
                case .none: return 0
                case .ambient: return 18
                case .attention: return 16
                case .urgent: return 14
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
                .shadow(color: Color.black.opacity(0.35), radius: r2, x: 0, y: 2)
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
    /// Default cards use neutral depth; glow is applied selectively.
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
        content
            .background(PerchTheme.cardBackground)
            .cornerRadius(PerchTheme.Card.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                    .stroke(PerchTheme.border, lineWidth: PerchTheme.Card.borderWidth)
            )
            // Default shadow: neutral depth. Glow is applied selectively.
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.55 : 0.06),
                radius: colorScheme == .dark ? 10 : 8,
                x: 0,
                y: colorScheme == .dark ? 4 : 2
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.06),
                radius: 6,
                x: 0,
                y: 2
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
                        .stroke(PerchTheme.accent.opacity(0.3), lineWidth: 1.5)
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
                    colors: [PerchTheme.steel.opacity(0.35), PerchTheme.accent.opacity(0.50)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 2)
                .clipShape(RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius))
            }
            .perchGlow(.ambient)
    }
}
