import SwiftUI

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    let width = geometry.size.width
                    LinearGradient(
                        colors: [
                            .clear,
                            PerchTheme.accent.opacity(0.04),
                            PerchTheme.accent.opacity(0.10),
                            PerchTheme.accent.opacity(0.04),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: width * 0.6)
                    .offset(x: width * phase)
                    .clipped()
                }
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 2.0
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Skeleton Shapes

struct SkeletonLine: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(PerchTheme.cardInnerBackground)
            .frame(width: width, height: height)
            .shimmer()
    }
}

struct SkeletonCircle: View {
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(PerchTheme.cardInnerBackground)
            .frame(width: size, height: size)
            .shimmer()
    }
}

struct SkeletonRect: View {
    var width: CGFloat? = nil
    var height: CGFloat = 80
    var cornerRadius: CGFloat = PerchTheme.Card.innerCornerRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(PerchTheme.cardInnerBackground)
            .frame(width: width, height: height)
            .shimmer()
    }
}

// MARK: - Skeleton Card Templates

struct SkeletonSingleValueCard: View {
    var body: some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            SkeletonCircle(size: 24)
            SkeletonLine(width: 60, height: 12)
            SkeletonLine(width: 50, height: 20)
            Spacer()
            SkeletonLine(width: 40, height: 12)
        }
        .padding(.horizontal, PerchTheme.Spacing.large)
        .padding(.vertical, PerchTheme.Spacing.medium)
        .cardStyle()
    }
}

struct SkeletonChartCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonLine(width: 80, height: 12)
                    SkeletonLine(width: 60, height: 28)
                }
                Spacer()
                SkeletonRect(width: 60, height: 28, cornerRadius: 8)
            }
            SkeletonRect(height: 110, cornerRadius: 8)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonRect(height: 36, cornerRadius: 10)
                }
            }
        }
        .padding(PerchTheme.Spacing.large)
        .cardStyle()
    }
}

struct SkeletonCaloriesCard: View {
    var body: some View {
        HStack(spacing: 20) {
            SkeletonCircle(size: 90)
            VStack(alignment: .leading, spacing: 10) {
                SkeletonLine(width: 100, height: 16)
                SkeletonLine(height: 12)
                SkeletonLine(height: 12)
                SkeletonLine(width: 40, height: 10)
            }
            Spacer()
        }
        .padding(PerchTheme.Spacing.large)
        .cardStyle()
    }
}

struct SkeletonMacrosCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SkeletonLine(width: 100, height: 16)
            ForEach(0..<3, id: \.self) { _ in
                VStack(spacing: 6) {
                    HStack {
                        SkeletonCircle(size: 8)
                        SkeletonLine(width: 50, height: 12)
                        Spacer()
                        SkeletonLine(width: 70, height: 12)
                    }
                    SkeletonRect(height: 8, cornerRadius: 4)
                }
            }
            HStack {
                SkeletonLine(width: 80, height: 10)
                Spacer()
                SkeletonLine(width: 60, height: 12)
            }
        }
        .padding(PerchTheme.Spacing.large)
        .cardStyle()
    }
}

struct SkeletonDeliveryCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                SkeletonRect(width: 40, height: 40, cornerRadius: 10)
                VStack(alignment: .leading, spacing: 4) {
                    SkeletonLine(width: 140, height: 14)
                    SkeletonLine(width: 100, height: 11)
                }
                Spacer()
                SkeletonLine(width: 60, height: 12)
            }
            SkeletonRect(height: 50, cornerRadius: 8)
        }
        .padding(PerchTheme.Spacing.large)
        .cardStyle()
    }
}

struct SkeletonEventCard: View {
    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(PerchTheme.cardInnerBackground)
                .frame(width: 4)
                .shimmer()
            VStack(alignment: .leading, spacing: 6) {
                SkeletonLine(width: 100, height: 11)
                SkeletonLine(width: 160, height: 14)
                SkeletonLine(width: 80, height: 11)
            }
            .padding(.horizontal, PerchTheme.Spacing.large)
            .padding(.vertical, 18)
        }
        .cardStyle()
    }
}

struct SkeletonBookmarkCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
            SkeletonRect(width: 36, height: 36, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonLine(height: 14)
                SkeletonLine(width: 120, height: 11)
                HStack(spacing: 6) {
                    SkeletonRect(width: 50, height: 18, cornerRadius: 6)
                    SkeletonRect(width: 40, height: 18, cornerRadius: 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(PerchTheme.Spacing.large)
        .cardStyle()
    }
}

// MARK: - Section Skeleton Loaders

struct SkeletonHealthSection: View {
    var body: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            SkeletonCaloriesCard()
            SkeletonMacrosCard()
            SkeletonChartCard()
            SkeletonChartCard()
        }
    }
}

struct SkeletonDeliveriesSection: View {
    var body: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            SkeletonDeliveryCard()
            SkeletonDeliveryCard()
        }
    }
}

struct SkeletonCalendarSection: View {
    var body: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            SkeletonEventCard()
            SkeletonEventCard()
            SkeletonEventCard()
        }
    }
}

struct SkeletonHomeSection: View {
    var body: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            SkeletonRect(height: 56, cornerRadius: PerchTheme.Card.cornerRadius)
            SkeletonDeliveryCard()
            SkeletonEventCard()
            SkeletonSingleValueCard()
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            SkeletonSingleValueCard()
            SkeletonCaloriesCard()
            SkeletonMacrosCard()
            SkeletonChartCard()
            SkeletonDeliveryCard()
            SkeletonEventCard()
            SkeletonBookmarkCard()
        }
        .padding()
    }
    .background(PerchTheme.background)
}
