import SwiftUI

// MARK: - SwipeActionsContainer
//
// Swipe-to-reveal action affordance. Built on a UIKit-bridged pan
// recognizer (see HorizontalPanReader.swift) instead of SwiftUI's
// DragGesture because SwiftUI gestures cannot release after capture.
// The orders list lives inside HubTab's page-style TabView (which
// pages on horizontal pan) AND a vertical ScrollView — we need to
// claim horizontal pans WITHOUT eating vertical scrolls.
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

    /// Persistent offset (committed) — survives between drags when
    /// the row is in the open state. Live drag deltas are tracked
    /// separately in `liveDelta`.
    @State private var offset: CGFloat = 0
    @State private var liveDelta: CGFloat = 0
    @State private var isOpen = false

    /// Width of the action column (per button).
    private let buttonWidth: CGFloat = 84
    /// Reveal threshold: drag past this to snap fully open.
    private var openThreshold: CGFloat { totalActionsWidth * 0.4 }
    /// Auto-commit threshold: drag past this and we fire the trailing
    /// (most-destructive) action immediately on release.
    private var commitThreshold: CGFloat { totalActionsWidth * 1.6 }

    private var totalActionsWidth: CGFloat {
        CGFloat(actions.count) * buttonWidth
    }

    var body: some View {
        let totalOffset = offset + liveDelta

        ZStack(alignment: .trailing) {
            // Action panel — sized to total reveal width, clipped on right edge.
            actionPanel
                .frame(width: max(0, -totalOffset))
                .clipped()
                .opacity(min(1, -totalOffset / max(1, totalActionsWidth * 0.3)))

            // Content layer — shifted leftward by the drag.
            content()
                .offset(x: totalOffset)
                .background(panReader)
                .simultaneousGesture(
                    // Tap on body while open closes without firing an action.
                    TapGesture().onEnded { if isOpen { close() } }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onDisappear { close() }
    }

    private var actionPanel: some View {
        HStack(spacing: 0) {
            ForEach(actions) { action in
                Button {
                    PerchHaptics.light()
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

    private var panReader: some View {
        HorizontalPanReader(
            onChanged: { translation in
                handleDragChanged(translation)
            },
            onEnded: { translation in
                handleDragEnded(translation)
            }
        )
    }

    private func handleDragChanged(_ translation: CGSize) {
        // Translation is the cumulative delta from where the drag
        // started. Map it onto our live offset, clamping so the
        // content doesn't overshoot in either direction.
        let raw = translation.width
        if isOpen {
            // From open: positive raw = closing motion. Clamp [0, totalActionsWidth]
            // (max positive recovers closed position).
            liveDelta = max(0, min(raw, totalActionsWidth))
        } else {
            // From closed: only negative drags reveal. Positive drags ignored.
            liveDelta = min(0, raw)
        }
    }

    private func handleDragEnded(_ translation: CGSize) {
        let raw = translation.width

        // Auto-commit: hard leftward drag fires the destructive action.
        if !isOpen,
           let trailing = actions.last,
           trailing.role == .destructive,
           -raw >= commitThreshold {
            PerchHaptics.medium()
            trailing.handler()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                liveDelta = 0
                offset = 0
                isOpen = false
            }
            return
        }

        let final = offset + raw

        if isOpen {
            // We were open. Positive raw above threshold = close.
            if raw > openThreshold {
                close()
            } else {
                snapOpen()
            }
        } else {
            if -final > openThreshold {
                snapOpen()
            } else {
                close()
            }
        }
    }

    private func snapOpen() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            liveDelta = 0
            offset = -totalActionsWidth
            isOpen = true
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            liveDelta = 0
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
