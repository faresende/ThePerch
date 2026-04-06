import SwiftUI

// MARK: - New Card Style

/// Lighter, more breathable card style for content cards.
/// Reduced corner radius, lighter shadow, subtle accent top border.
/// Uses `.glassEffect(.periodic, in:)` on iOS 26+ with graceful fallback.
struct NewCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let cardShape = RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)

        content
            .background(cardBackground(for: cardShape))
            .overlay(alignment: .top) {
                accentTopBorder
            }
            .overlay(
                cardShape
                    .stroke(
                        LinearGradient(
                            colors: [
                                PerchTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.08),
                                PerchTheme.border.opacity(colorScheme == .dark ? 0.80 : 0.50)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: PerchTheme.Card.borderWidth
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06),
                radius: 4,
                x: 0,
                y: 2
            )
    }

    // MARK: - Background

    @ViewBuilder
    private func cardBackground(for shape: some Shape) -> some View {
        shape
            .fill(.ultraThinMaterial)
            .opacity(colorScheme == .dark ? 0.72 : 0.88)
    }

    // MARK: - Accent Top Border

    private var accentTopBorder: some View {
        LinearGradient(
            colors: [
                PerchTheme.accent.opacity(colorScheme == .dark ? 0.45 : 0.28),
                PerchTheme.accent.opacity(0.00)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous))
    }
}

// MARK: - View Extension

extension View {
    /// Apply the new lighter card style with subtle accent top border.
    func newCardStyle() -> some View {
        modifier(NewCardStyle())
    }
}

// MARK: - Lightweight Card Modifier

/// Even lighter card for inline content — minimal shadow, no border, tight radius.
struct LightCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        content
            .background(shape.fill(PerchTheme.cardInnerBackground))
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.14 : 0.04),
                radius: 2,
                x: 0,
                y: 1
            )
    }
}

extension View {
    /// Ultra-light card for inline items (checklist rows, list cells).
    func lightCardStyle() -> some View {
        modifier(LightCardStyle())
    }
}

// MARK: - Preview

// Preview removed - causes macro expansion issues in some Xcode versions
