import SwiftUI

// MARK: - UndoCorrectionToast
//
// Bottom-of-screen toast shown for 5 seconds after a `.notAnOrder`
// correction fires. Tapping "Undo" cancels the correction (via
// OrdersService.cancelCorrection) and restores the order row.
//
// Lifecycle is owned by OrdersViewModel:
//   - viewModel.activeUndoReceipt set when correction fires.
//   - View binds to that, presents toast.
//   - 5s timer in viewModel auto-clears the receipt.
//   - User tap "Undo" calls viewModel.cancelActiveUndo() → cancels.
//
// Phase 1 corrections-and-rules.

struct UndoCorrectionToast: View {
    @Environment(\.perchPalette) private var palette

    let receipt: CorrectionReceipt
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: receipt.kind.actionSymbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(palette.faint)

            Text(message)
                .font(PerchTheme.Font.caption)
                .foregroundColor(palette.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Undo") {
                PerchHaptics.light()
                onUndo()
            }
            .font(PerchTheme.Font.caption.weight(.semibold))
            .foregroundColor(palette.kinetic)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(palette.kinetic.opacity(0.12))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.line.opacity(0.4), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var message: String {
        switch receipt.kind {
        case .notAnOrder:       return "Order dismissed."
        case .wrongTracking:    return "Tracking cleared."
        case .alreadyDelivered: return "Marked delivered."
        }
    }
}

// MARK: - View modifier

extension View {
    /// Overlay an undo toast at the bottom edge while a CorrectionReceipt is active.
    /// Pass `nil` to hide. The toast handles its own animations + tap targets.
    func undoCorrectionToast(
        receipt: CorrectionReceipt?,
        onUndo: @escaping () -> Void
    ) -> some View {
        self.overlay(alignment: .bottom) {
            if let receipt {
                UndoCorrectionToast(receipt: receipt, onUndo: onUndo)
                    .padding(.bottom, 24)  // clears tab-bar safe area
                    .animation(.spring(response: 0.4, dampingFraction: 0.78), value: receipt.id)
            }
        }
    }
}
