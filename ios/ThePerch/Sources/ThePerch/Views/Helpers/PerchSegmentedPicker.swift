import SwiftUI

// MARK: - PerchPickerOption

/// A single option in a PerchSegmentedPicker.
struct PerchPickerOption<T: Hashable>: Hashable, Identifiable {
    let title: String
    let value: T
    var id: T { value }
}

// MARK: - PerchSegmentedPicker

/// A custom pill-style segmented picker inspired by iOS Mail's mailbox filter.
/// Uses `matchedGeometryEffect` for a smooth sliding selection indicator.
/// Drop-in replacement for `Picker(.segmented)` with a more polished look.
struct PerchSegmentedPicker<T: Hashable>: View {
    let options: [PerchPickerOption<T>]
    @Binding var selection: T
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = selection == option.value

                Button {
                    PerchHaptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.title)
                        .font(PerchTheme.Font.body.weight(.medium))
                        .foregroundColor(isSelected ? PerchTheme.accentForeground : PerchTheme.textSecondary)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(PerchTheme.accent)
                                    .matchedGeometryEffect(id: "picker-indicator", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(PerchTheme.cardInnerBackground)
        )
    }
}

// MARK: - Convenience initializer for CaseIterable String-backed enums

extension PerchSegmentedPicker where T: RawRepresentable & CaseIterable, T.RawValue == String, T.AllCases: RandomAccessCollection {
    /// Creates a picker from a CaseIterable String-backed enum.
    /// Each case's `rawValue` becomes the displayed title.
    init(enumSelection selection: Binding<T>) {
        self.options = T.allCases.map { .init(title: $0.rawValue, value: $0) }
        self._selection = selection
    }
}
