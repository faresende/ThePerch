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
            dark: UIColor(red: 0.05, green: 0.05, blue: 0.055, alpha: 1)      // #0d0d0e
        )
    }

    /// Elevated surface for cards
    static var cardBackground: Color {
        adaptive(
            light: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),        // #FFFFFF
            dark: UIColor(red: 0.09, green: 0.09, blue: 0.095, alpha: 1)      // #171718
        )
    }

    /// Inner surface for items within cards (checklist rows, selectors)
    static var cardInnerBackground: Color {
        adaptive(
            light: UIColor(red: 0.949, green: 0.945, blue: 0.937, alpha: 1),  // #F2F1EF
            dark: UIColor(red: 0.12, green: 0.12, blue: 0.125, alpha: 1)      // #1f1f20
        )
    }

    /// Card hover/pressed state
    static var cardHover: Color {
        adaptive(
            light: UIColor(red: 0.929, green: 0.925, blue: 0.918, alpha: 1),  // #EDECEB
            dark: UIColor(red: 0.15, green: 0.15, blue: 0.155, alpha: 1)      // #262627
        )
    }

    /// Primary text — near white (dark) / near black (light)
    static var textPrimary: Color {
        adaptive(
            light: UIColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1),  // #1A1A1A
            dark: UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)       // #f2f2f2
        )
    }

    /// Secondary text — neutral gray (WCAG AA compliant, ≥4.5:1 on cards)
    static var textSecondary: Color {
        adaptive(
            light: UIColor(red: 0.420, green: 0.420, blue: 0.440, alpha: 1),  // #6B6B70
            dark: UIColor(red: 0.541, green: 0.541, blue: 0.561, alpha: 1)    // #8A8A8F
        )
    }

    /// Tertiary text — dim (WCAG AA compliant, ≥4.5:1 on background)
    static var textTertiary: Color {
        adaptive(
            light: UIColor(red: 0.557, green: 0.557, blue: 0.576, alpha: 1),  // #8E8E93
            dark: UIColor(red: 0.451, green: 0.451, blue: 0.471, alpha: 1)    // #737378
        )
    }

    /// Accent — warm amber/gold, slightly deeper in light mode for contrast
    static var accent: Color {
        adaptive(
            light: UIColor(red: 0.831, green: 0.580, blue: 0.051, alpha: 1),  // #D4940D
            dark: UIColor(red: 0.96, green: 0.68, blue: 0.15, alpha: 1)       // #f5ad26
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
            dark: UIColor(red: 0.96, green: 0.68, blue: 0.15, alpha: 0.13)    // amber glow
        )
    }

    /// Success — slightly deeper in light mode
    static var success: Color {
        adaptive(
            light: UIColor(red: 0.114, green: 0.541, blue: 0.235, alpha: 1),  // #1D8A3C
            dark: UIColor(red: 0.22, green: 0.75, blue: 0.45, alpha: 1)       // #38bf73
        )
    }

    /// Warning — warm orange, visually distinct from accent amber
    static var warning: Color {
        adaptive(
            light: UIColor(red: 0.769, green: 0.498, blue: 0.039, alpha: 1),  // #C47F0A
            dark: UIColor(red: 0.922, green: 0.600, blue: 0.149, alpha: 1)    // #EB9926
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
            dark: UIColor(red: 0.90, green: 0.33, blue: 0.33, alpha: 1)       // #e65454
        )
    }

    /// Border — subtle, neutral
    static var border: Color {
        adaptive(
            light: UIColor(red: 0.847, green: 0.839, blue: 0.827, alpha: 1),  // #D8D6D3
            dark: UIColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)       // #29292b
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

// MARK: - View Extensions for Common Styling

extension View {
    /// Apply card styling with adaptive shadows.
    /// Dark mode: ambient amber glow + deep shadow.
    /// Light mode: subtle neutral shadow, no glow.
    func cardStyle() -> some View {
        modifier(CardStyleModifier())
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
            .shadow(
                color: colorScheme == .dark
                    ? PerchTheme.accentGlow        // amber glow in dark
                    : Color.black.opacity(0.04),   // subtle neutral in light
                radius: colorScheme == .dark ? 16 : 8,
                x: 0,
                y: colorScheme == .dark ? 0 : 2
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
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
        }
    }
}
