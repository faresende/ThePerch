import SwiftUI
import Combine

// MARK: - Tab Bar State

/// Observable object shared between MainTabView (source of truth) and tab content
/// ScrollViews (which drive the collapse via scroll direction).
///
/// Usage:
///   1. In MainTabView: @StateObject private var tabBarState = TabBarState()
///      .environmentObject(tabBarState)
///   2. In LiquidGlassTabBar: @EnvironmentObject private var tabBarState: TabBarState
///   3. In tab content ScrollViews: @EnvironmentObject private var tabBarState: TabBarState
///      .trackScrollForTabBar()
@MainActor
final class TabBarState: ObservableObject {
    /// `true` when the floating tab bar pill is collapsed.
    @Published var isCollapsed: Bool = false

    @Published var lastToggleTime: Date = .distantPast
    @Published var accumulatedDelta: CGFloat = 0
    @Published var previousOffset: CGFloat = 0

    private let downThreshold: CGFloat = 20
    private let upThreshold: CGFloat = 10
    private let debounceInterval: TimeInterval = 0.3

    /// Whether we've received a stable first offset (ignore initial layout jumps).
    private var hasStabilized = false
    private var stableFrameCount = 0

    func handleScrollOffset(_ currentOffset: CGFloat) {
        let now = Date()
        let delta = currentOffset - previousOffset
        previousOffset = currentOffset

        // Ignore the first few frames — layout can produce large jumps.
        if !hasStabilized {
            stableFrameCount += 1
            if stableFrameCount > 3 {
                hasStabilized = true
            }
            return
        }

        let atTop = currentOffset <= 0

        guard now.timeIntervalSince(lastToggleTime) >= debounceInterval else { return }

        if delta < 0 {
            // Scrolling UP (content moving down)
            if atTop {
                if isCollapsed {
                    isCollapsed = false
                    lastToggleTime = now
                    accumulatedDelta = 0
                }
                return
            }

            accumulatedDelta += abs(delta)
            if accumulatedDelta >= upThreshold {
                if isCollapsed {
                    isCollapsed = false
                    lastToggleTime = now
                }
                accumulatedDelta = 0
            }
        } else if delta > 0 {
            // Scrolling DOWN (content moving up)
            accumulatedDelta += delta
            if accumulatedDelta >= downThreshold {
                if !isCollapsed {
                    isCollapsed = true
                    lastToggleTime = now
                    accumulatedDelta = 0
                }
            }
        }
    }
}

// MARK: - Scroll Collapse Tracker

/// Tracks scroll direction in a ScrollView and collapses the floating tab bar pill.
extension View {
    /// Attaches scroll-direction tracking to a ScrollView for tab-bar collapse behavior.
    /// Uses `TabBarState` from the environment to update the collapsed state.
    func trackScrollForTabBar() -> some View {
        modifier(ScrollOffsetTrackerModifier())
    }
}

private struct ScrollOffsetTrackerModifier: ViewModifier {
    @EnvironmentObject private var tabBarState: TabBarState

    @State private var lastOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    let globalMinY = geo.frame(in: .global).minY

                    Color.clear
                        .onChange(of: globalMinY) { _, newValue in
                            let offset = -newValue
                            tabBarState.handleScrollOffset(offset)
                        }
                }
            )
    }
}

// MARK: - Tab Item Model

struct LiquidGlassTabItem: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String

    static let items: [LiquidGlassTabItem] = [
        LiquidGlassTabItem(id: "today", title: "Today", systemImage: "house.fill"),
        LiquidGlassTabItem(id: "health", title: "Health", systemImage: "heart.fill"),
        LiquidGlassTabItem(id: "hub", title: "Hub", systemImage: "square.grid.2x2.fill"),
        LiquidGlassTabItem(id: "settings", title: "Settings", systemImage: "gearshape.fill"),
    ]
}

// MARK: - Liquid Glass Tab Bar

/// Apple's Liquid Glass floating pill tab bar — iOS 26+ native style.
/// A frosted-glass capsule that floats above content, centered at the bottom.
/// Selected tab animates with matchedGeometryEffect; scrolls collapse the pill.
struct LiquidGlassTabBar: View {
    @Binding var selectedId: String
    @Binding var isCollapsed: Bool
    let onSelect: ((String) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var tabNamespace

    @State private var pressedId: String?
    @State private var appears: Bool = false

    // Pill dimensions
    private let pillWidth: CGFloat = 280
    private let pillHeight: CGFloat = 56
    private let iconSize: CGFloat = 22
    private let labelSize: CGFloat = 10

    init(selectedId: Binding<String>, isCollapsed: Binding<Bool> = .constant(false), onSelect: ((String) -> Void)? = nil) {
        self._selectedId = selectedId
        self._isCollapsed = isCollapsed
        self.onSelect = onSelect
    }

    var body: some View {
        floatingPill
            .opacity(appears ? 1 : 0)
            .scaleEffect(appears ? 1 : 0.85, anchor: .center)
            .onAppear {
                withAnimation(.easeOut(duration: 0.35)) {
                    appears = true
                }
            }
    }

    // MARK: - Floating Pill

    private var floatingPill: some View {
        let shape = Capsule()

        return ZStack {
            // Frosted glass background — no opaque backing, content blurs through
            shape
                .fill(.ultraThinMaterial)
                .opacity(0.85)

            // Subtle edge stroke
            shape
                .stroke(
                    edgeStrokeColor,
                    lineWidth: 0.5
                )

            // Tab content
            HStack(spacing: 0) {
                ForEach(LiquidGlassTabItem.items) { item in
                    tabButton(for: item)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: pillWidth, height: pillHeight)

            // Selected indicator pill
            selectedIndicator
        }
        .frame(width: pillWidth, height: pillHeight)
        .shadow(
            color: Color.black.opacity(0.12),
            radius: 16,
            x: 0,
            y: 4
        )
        .scaleEffect(isCollapsed ? 0.7 : 1.0, anchor: .center)
        .opacity(isCollapsed ? 0.0 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isCollapsed)
    }

    // MARK: - Selected Indicator

    private var selectedIndicator: some View {
        let shape = Capsule()

        return GeometryReader { geo in
            let tabCount = CGFloat(LiquidGlassTabItem.items.count)
            let tabWidth = (pillWidth - 24) / tabCount // 24 = horizontal padding (12+12)

            let selectedIndex = Double(
                LiquidGlassTabItem.items
                    .firstIndex { $0.id == selectedId }
                    .map { $0 } ?? 0
            )

            shape
                .fill(selectedIndicatorColor)
                .frame(width: tabWidth, height: pillHeight - 20)
                .clipShape(shape)
                .position(
                    x: 12 + tabWidth * selectedIndex + tabWidth / 2,
                    y: pillHeight / 2
                )
                .matchedGeometryEffect(id: "tabIndicator", in: tabNamespace, isSource: false)
        }
        .frame(width: pillWidth, height: pillHeight)
    }

    // MARK: - Tab Button

    private func tabButton(for item: LiquidGlassTabItem) -> some View {
        let isSelected = selectedId == item.id
        let isPressed = pressedId == item.id
        let scale: CGFloat = isPressed ? 0.95 : 1.0

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedId = item.id
            }
            PerchHaptics.selection()
            onSelect?(item.id)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.systemImage)
                    .font(.system(size: iconSize, weight: .medium))
                    .imageScale(.medium)
                    .foregroundStyle(tabForeground(isSelected: isSelected))
                    .matchedGeometryEffect(id: item.id, in: tabNamespace, isSource: true)

                Text(item.title)
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundStyle(tabForeground(isSelected: isSelected))
            }
            .frame(maxWidth: .infinity)
            .scaleEffect(scale)
            .contentShape(Rectangle())
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
    }

    // MARK: - Adaptive Colors

    private func tabForeground(isSelected: Bool) -> Color {
        if isSelected {
            return colorScheme == .dark ? .white : PerchTheme.accent
        }
        return PerchTheme.textTertiary
    }

    private var selectedIndicatorColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.20)
            : PerchTheme.accent.opacity(0.15)
    }

    private var edgeStrokeColor: Color {
        Color.white.opacity(0.15)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var selected = "today"
        @State private var collapsed = false

        var body: some View {
            ZStack {
                PerchTheme.background.ignoresSafeArea()

                VStack {
                    Spacer()
                    HStack {
                        Button("Collapse") {
                            collapsed.toggle()
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                    LiquidGlassTabBar(selectedId: $selected, isCollapsed: $collapsed)
                }
            }
        }
    }

    return PreviewWrapper()
}
