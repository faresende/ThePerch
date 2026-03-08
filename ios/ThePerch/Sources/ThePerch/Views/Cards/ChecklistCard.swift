import SwiftUI

/// Displays a toggle-able checklist with progress bar and individual row cells.
/// Precisely matches the 21st.dev reference: near-black card, each item in its
/// own bordered cell, amber checkboxes, progress bar with percentage.
struct ChecklistCard: View {
    let title: String
    @State var items: [ChecklistItem]

    var completedCount: Int {
        items.filter { $0.done }.count
    }

    var progressPercent: Double {
        guard !items.isEmpty else { return 0 }
        return Double(completedCount) / Double(items.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text(title)
                .font(PerchTheme.Font.title)
                .foregroundColor(PerchTheme.textPrimary)

            // Subtitle row: count left, percentage right
            HStack {
                Text("\(completedCount) of \(items.count) completed")
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textSecondary)

                Spacer()

                Text("\(Int(progressPercent * 100))%")
                    .font(PerchTheme.Font.headingNumeric)
                    .foregroundColor(PerchTheme.accent)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PerchTheme.cardInnerBackground)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(PerchTheme.accent)
                        .frame(width: max(0, geometry.size.width * progressPercent))
                        .animation(
                            PerchMotion.prefersReduced ? .none : .easeInOut(duration: 0.3),
                            value: progressPercent
                        )
                }
            }
            .frame(height: 8)

            // Items
            VStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            items[index].done.toggle()
                        }
                    } label: {
                        HStack(spacing: 14) {
                            // Circular checkbox
                            ZStack {
                                if item.done {
                                    Circle()
                                        .fill(PerchTheme.accent)
                                        .frame(width: 24, height: 24)
                                        .shadow(
                                            color: PerchTheme.accent.opacity(0.3),
                                            radius: 4
                                        )

                                    Image(systemName: "checkmark")
                                        .font(PerchTheme.Font.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                } else {
                                    Circle()
                                        .strokeBorder(
                                            PerchTheme.textTertiary,
                                            lineWidth: 2
                                        )
                                        .frame(width: 24, height: 24)
                                }
                            }

                            // Item text
                            Text(item.text)
                                .font(PerchTheme.Font.body)
                                .foregroundColor(
                                    item.done
                                        ? PerchTheme.textTertiary
                                        : PerchTheme.textPrimary
                                )
                                .strikethrough(item.done, color: PerchTheme.textTertiary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Spacer()
                        }
                        .padding(.horizontal, PerchTheme.Spacing.medium)
                        .padding(.vertical, PerchTheme.Spacing.medium)
                        .background(PerchTheme.cardInnerBackground)
                        .cornerRadius(PerchTheme.Card.innerCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                                .stroke(PerchTheme.border, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(PerchTheme.Spacing.large)
        .cardStyle()
    }
}

// MARK: - Preview

#Preview {
    ChecklistCard(
        title: "Daily Tasks",
        items: [
            ChecklistItem(text: "Review morning standup notes", done: true),
            ChecklistItem(text: "Complete code review", done: true),
            ChecklistItem(text: "Update project documentation", done: false),
            ChecklistItem(text: "Prepare for client meeting", done: false),
            ChecklistItem(text: "Deploy to staging environment", done: false),
        ]
    )
    .padding(PerchTheme.Spacing.large)
    .background(PerchTheme.background)
    .ignoresSafeArea()
}
