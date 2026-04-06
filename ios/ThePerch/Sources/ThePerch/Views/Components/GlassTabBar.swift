import SwiftUI

// MARK: - Tab Item Model

struct GlassTabItem: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String

    static let items: [GlassTabItem] = [
        GlassTabItem(id: "today", title: "Today", systemImage: "house.fill"),
        GlassTabItem(id: "health", title: "Health", systemImage: "heart.fill"),
        GlassTabItem(id: "hub", title: "Hub", systemImage: "square.grid.2x2.fill"),
        GlassTabItem(id: "settings", title: "Settings", systemImage: "gearshape.fill"),
    ]
}

// MARK: - Glass Tab Bar

/// Glass-styled bottom tab bar with ultraThinMaterial background,
/// accent gradient top edge, and smooth press animations.
struct GlassTabBar: View {
    @Binding var selectedId: String
    let onSelect: ((String) -> Void)?

    @State private var pressedId: String?


    init(selectedId: Binding<String>, onSelect: ((String) -> Void)? = nil) {
        self._selectedId = selectedId
        self.onSelect = onSelect
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Fully opaque edge-to-edge backing (includes home indicator zone)
            Rectangle()
                .fill(PerchTheme.background)

            HStack(spacing: 0) {
                ForEach(GlassTabItem.items) { item in
                    tabButton(for: item)
                }
            }
            .padding(.horizontal, PerchTheme.Spacing.medium)
            .padding(.top, PerchTheme.Spacing.xSmall)
            .padding(.bottom, PerchTheme.Spacing.small)
            .frame(height: PerchTheme.TabBar.height)
        }
        .frame(maxWidth: .infinity)
        .frame(height: PerchTheme.TabBar.height)
        .shadow(color: .black.opacity(0.06), radius: 8, y: -2)
    }

    // MARK: - Background

    @ViewBuilder
    private var tabBarBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        shape
            .fill(PerchTheme.background)
            .shadow(color: .black.opacity(0.06), radius: 8, y: -2)
    }

    // MARK: - Top Accent Line

    private var topAccentLine: some View {
        LinearGradient(
            colors: [
                PerchTheme.accent.opacity(0.60),
                PerchTheme.accent.opacity(0.20),
                PerchTheme.accent.opacity(0.00)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 0.5)
        .padding(.horizontal, PerchTheme.Spacing.mediumLarge)
        .offset(y: -PerchTheme.Spacing.xSmall)
    }

    // MARK: - Tab Button

    private func tabButton(for item: GlassTabItem) -> some View {
        let isSelected = selectedId == item.id
        let isPressed = pressedId == item.id
        let scale: CGFloat = isPressed ? 0.92 : 1.0

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedId = item.id
            }
            PerchHaptics.selection()
            onSelect?(item.id)
        } label: {
            VStack(spacing: PerchTheme.Spacing.xxxSmall) {
                Image(systemName: item.systemImage)
                    .font(.system(size: PerchTheme.TabBar.iconSize, weight: .medium))
                    .foregroundStyle(isSelected ? PerchTheme.accent : PerchTheme.textTertiary)
                    .imageScale(.medium)

                Text(item.title)
                    .font(.system(size: PerchTheme.TabBar.labelSize, weight: .medium))
                    .foregroundStyle(isSelected ? PerchTheme.accent : PerchTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .scaleEffect(scale)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if pressedId != item.id {
                        pressedId = item.id
                    }
                }
                .onEnded { _ in
                    pressedId = nil
                }
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressed)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selected = "today"

        var body: some View {
            ZStack {
                PerchTheme.background.ignoresSafeArea()

                VStack {
                    Spacer()
                    GlassTabBar(selectedId: $selected)
                }
            }
        }
    }

    return PreviewWrapper()
}
