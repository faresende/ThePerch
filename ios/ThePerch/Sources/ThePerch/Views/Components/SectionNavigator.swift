import SwiftUI

/// A scrollable pill bar for navigating between dashboard sections.
/// Active pill is filled with accent color; tapping navigates to that section.
struct SectionNavigator: View {
    @Binding var selectedIndex: Int
    let sectionNames: [String]

    @Namespace private var pillNamespace

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    ForEach(Array(sectionNames.enumerated()), id: \.offset) { index, name in
                        PillButton(
                            title: name,
                            isActive: selectedIndex == index,
                            namespace: pillNamespace
                        ) {
                            PerchHaptics.selection()
                            PerchMotion.withOptionalAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedIndex = index
                            }
                        }
                        .id(index)
                    }
                }
                .padding(.vertical, PerchTheme.Spacing.xSmall)
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .onChange(of: selectedIndex) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    proxy.scrollTo(selectedIndex, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Pill Button

private struct PillButton: View {
    let title: String
    let isActive: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PerchTheme.Font.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundColor(isActive ? PerchTheme.accentForeground : PerchTheme.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, PerchTheme.Spacing.medium)
                .padding(.vertical, PerchTheme.Spacing.xSmall)
                .background {
                    if isActive {
                        Capsule()
                            .fill(PerchTheme.accent)
                            .matchedGeometryEffect(id: "activePill", in: namespace)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    SectionNavigator(
        selectedIndex: .constant(0),
        sectionNames: ["Home", "Health", "Deliveries", "Calendar", "Bookmarks", "Admin", "Legal"]
    )
    .background(PerchTheme.background)
}
