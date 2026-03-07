import SwiftUI

/// Centralized theme configuration for The Perch app.
/// Near-black dark theme with warm amber accent and ambient glow effects.
/// Designed to match the 21st.dev card reference designs.
struct PerchTheme {
    // MARK: - Colors

    /// Main background — near black, neutral (no blue/purple tint)
    static var background: Color {
        Color(red: 0.05, green: 0.05, blue: 0.055)  // #0d0d0e
    }

    /// Elevated surface for cards — neutral dark gray, no purple
    static var cardBackground: Color {
        Color(red: 0.09, green: 0.09, blue: 0.095)  // #171718
    }

    /// Inner surface for items within cards (checklist rows, selectors)
    static var cardInnerBackground: Color {
        Color(red: 0.12, green: 0.12, blue: 0.125)  // #1f1f20
    }

    /// Card hover/pressed state
    static var cardHover: Color {
        Color(red: 0.15, green: 0.15, blue: 0.155)  // #262627
    }

    /// Primary text — near white
    static var textPrimary: Color {
        Color(red: 0.95, green: 0.95, blue: 0.95)  // #f2f2f2
    }

    /// Secondary text — neutral gray (WCAG AA compliant, ≥4.5:1 on cards)
    static var textSecondary: Color {
        Color(red: 0.541, green: 0.541, blue: 0.561)  // #8A8A8F
    }

    /// Tertiary text — dim (WCAG AA compliant, ≥4.5:1 on background)
    static var textTertiary: Color {
        Color(red: 0.451, green: 0.451, blue: 0.471)  // #737378
    }

    /// Accent — bright warm amber/gold (punchy, not washed out)
    static var accent: Color {
        Color(red: 0.96, green: 0.68, blue: 0.15)  // #f5ad26
    }

    /// Muted accent for tinted backgrounds
    static var accentMuted: Color {
        accent.opacity(0.15)
    }

    /// Accent glow — for ambient shadow/glow effects
    static var accentGlow: Color {
        accent.opacity(0.13)
    }

    /// Success
    static var success: Color {
        Color(red: 0.22, green: 0.75, blue: 0.45)  // #38bf73
    }

    /// Warning — warm orange, visually distinct from accent amber
    static var warning: Color {
        Color(red: 0.922, green: 0.600, blue: 0.149)  // #EB9926
    }

    /// Subtle warning background tint
    static var warningBackground: Color {
        warning.opacity(0.15)
    }

    /// Error
    static var error: Color {
        Color(red: 0.90, green: 0.33, blue: 0.33)  // #e65454
    }

    /// Border — subtle, neutral
    static var border: Color {
        Color(red: 0.16, green: 0.16, blue: 0.17)  // #29292b
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

// MARK: - View Extensions for Common Styling

extension View {
    /// Apply card styling with ambient warm glow.
    /// Glow spreads wide horizontally but is tight vertically so cards
    /// don't bleed into each other in a vertical stack.
    func cardStyle() -> some View {
        self
            .background(PerchTheme.cardBackground)
            .cornerRadius(PerchTheme.Card.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                    .stroke(PerchTheme.border, lineWidth: PerchTheme.Card.borderWidth)
            )
            // Wide horizontal amber glow (spread to the sides)
            .shadow(
                color: PerchTheme.accentGlow,
                radius: 16,
                x: 0,
                y: 0
            )
            // Dark depth shadow (tight, downward only)
            .shadow(
                color: Color.black.opacity(PerchTheme.Card.shadowOpacity),
                radius: 6,
                x: 0,
                y: 2
            )
    }

    /// Apply subtle border styling
    func cardBorder() -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                    .stroke(PerchTheme.border, lineWidth: 1)
            )
    }

    /// Staggered fade + slide-up card appear animation
    func cardAppear(index: Int, appeared: Bool) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(
                .spring(response: 0.45, dampingFraction: 0.8)
                .delay(Double(index) * 0.06),
                value: appeared
            )
    }

    /// Subtle scale on press for interactive cards
    func cardTapScale(_ isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
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
                withAnimation(.easeOut(duration: duration)) {
                    displayValue = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.easeOut(duration: duration)) {
                    displayValue = newValue
                }
            }
    }
}

// MARK: - Interactive Card Button Style

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    PerchHaptics.light()
                }
            }
    }
}
