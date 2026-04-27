import SwiftUI

// MARK: - SwipeActionsContainer
//
// Custom drag-to-reveal swipe-action affordance. Built bespoke (rather
// than `.swipeActions(edge:)`) because the Orders tab uses
// ScrollView+LazyVStack at the root, not a List — and SwiftUI's
// native swipeActions modifier requires a List ancestor.
//
// Interaction model (matches iOS Mail / Messages muscle memory):
//   1. User drags the row leftward.
//   2. Action buttons reveal from the trailing edge as the drag progresses.
//   3. On release:
//      - If dragged < threshold:    snaps back closed.
//      - If dragged ≥ threshold:    snaps to "fully revealed" (button-tap zone).
//      - If dragged ≥ commit-zone:  fires the most-destructive action immediately.
//   4. Tapping any revealed action runs its handler and animates closed.
//   5. Tapping the row body while open also closes (no action fires).
//
// Each action has: label, SF Symbol, tint, and `role` (.destructive
// flips the tap target's foreground to red and is a hint to assistive
// tech).
//
// Phase 1 corrections-and-rules. Used by OrdersGroupSection rows.

struct SwipeAction: Identifiable {
    enum Role { case normal, destructive }

    let id = UUID()
    let label: String
    let systemImage: String
    let tint: Color
    let role: Role
    let handler: () -> Void
}

struct SwipeActionsContainer<Content: View>: View {
    let actions: [SwipeAction]
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var isOpen = false
    @GestureState private var dragOffset: CGFloat = 0

    /// Width of the action column (per button).
    private let buttonWidth: CGFloat = 84
    /// Reveal threshold: drag past this to snap fully open.
    private var openThreshold: CGFloat { totalActionsWidth * 0.4 }
    /// Auto-commit threshold: drag past this and we fire the trailing
    /// (most-destructive) action immediately on release. Disabled when
    /// the trailing action isn't destructive — too risky for non-destructive
    /// actions.
    private var commitThreshold: CGFloat { totalActionsWidth * 1.6 }

    private var totalActionsWidth: CGFloat {
        CGFloat(actions.count) * buttonWidth
    }

    var body: some View {
        let totalOffset = offset + dragOffset

        ZStack(alignment: .trailing) {
            // Action panel — sized to total reveal width, clipped on right edge.
            actionPanel
                .frame(width: max(0, -totalOffset))
                .clipped()
                .opacity(min(1, -totalOffset / max(1, totalActionsWidth * 0.3)))
                .animation(.easeOut(duration: 0.18), value: dragOffset)

            // Content layer — shifted leftward by the drag.
            content()
                .offset(x: totalOffset)
                .gesture(dragGesture)
                .simultaneousGesture(
                    // Tap on body while open closes without firing an action.
                    TapGesture().onEnded { if isOpen { close() } }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // Auto-close if the parent view rebuilds (e.g. data refresh).
        // Without this, the open offset can persist when the row changes identity.
        .onDisappear { close() }
    }

    private var actionPanel: some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                Button {
                    action.handler()
                    close()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: action.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                        Text(action.label)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(.white)
                    .frame(width: buttonWidth)
                    .frame(maxHeight: .infinity)
                    .background(action.tint)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragOffset) { value, state, _ in
                // Only react to leftward drags. Rightward drags from
                // the closed state get ignored; rightward drags from
                // the open state pull the row back toward closed.
                let raw = value.translation.width
                if isOpen {
                    // Allow positive drag to close, but never overshoot 0.
                    state = max(0, min(raw, totalActionsWidth)) - 0  // [0, +totalActionsWidth]
                    state = max(0, min(state, totalActionsWidth))
                } else {
                    // Negative-only drag from closed.
                    state = min(0, raw)
                }
            }
            .onEnded { value in
                let raw = value.translation.width
                let final = offset + raw

                // Auto-commit: if the trailing-most action is destructive
                // and the user dragged hard enough, fire it.
                if let trailing = actions.last,
                   trailing.role == .destructive,
                   -raw >= commitThreshold {
                    trailing.handler()
                    close()
                    return
                }

                if isOpen {
                    // We're open. Decide based on positive drag (closing intent).
                    if raw > openThreshold {
                        close()
                    } else {
                        // Snap back to fully open.
                        snapOpen()
                    }
                } else {
                    // We're closed. Decide based on negative drag.
                    if -final > openThreshold {
                        snapOpen()
                    } else {
                        close()
                    }
                }
            }
    }

    private func snapOpen() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            offset = -totalActionsWidth
            isOpen = true
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            offset = 0
            isOpen = false
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        SwipeActionsContainer(actions: [
            SwipeAction(label: "Already delivered", systemImage: "checkmark.circle",
                        tint: .green, role: .normal, handler: { print("delivered") }),
            SwipeAction(label: "Wrong tracking", systemImage: "shippingbox.and.arrow.backward",
                        tint: .orange, role: .normal, handler: { print("tracking") }),
            SwipeAction(label: "Not an order", systemImage: "xmark.bin",
                        tint: .red, role: .destructive, handler: { print("dismiss") }),
        ]) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple").font(.headline)
                    Text("$12.99 · digital").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color(white: 0.97))
        }
        .padding()
    }
}
