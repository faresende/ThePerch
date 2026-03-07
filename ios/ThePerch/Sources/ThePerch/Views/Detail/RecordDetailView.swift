import SwiftUI

/// A lightweight in-app detail screen for any Record.
///
/// This intentionally starts simple:
/// - Shows the rendered card (non-interactive)
/// - Shows typed details when we can decode them
/// - Always provides raw JSON for debugging and transparency
struct RecordDetailView: View {
    let record: Record

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                // Primary card preview
                WidgetRouter(record: record, isInteractive: false)

                // Typed details
                detailsSection

                // Raw JSON
                rawJSONSection

                Spacer()
                    .frame(height: PerchTheme.Spacing.large)
            }
            .padding(.horizontal, PerchTheme.Spacing.large)
            .padding(.top, PerchTheme.Spacing.medium)
        }
        .background(PerchTheme.background.ignoresSafeArea())
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(PerchTheme.Font.body)
            }
        }
    }

    // MARK: - Details

    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            Text("Details")
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textPrimary)

            Group {
                if let measurement = record.asMeasurement() {
                    KeyValueList(rows: [
                        ("Value", formattedNumber(measurement.value)),
                        ("Unit", measurement.unit),
                        ("Timestamp", measurement.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "—"),
                        ("Target", measurement.target.map { formattedNumber($0) } ?? "—")
                    ])

                } else if let delivery = record.asDelivery() {
                    KeyValueList(rows: [
                        ("Carrier", delivery.carrier),
                        ("Status", delivery.status.capitalized),
                        ("Tracking", delivery.trackingNumber),
                        ("ETA", delivery.eta?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    ])

                    if let urlString = delivery.trackingUrl, let url = URL(string: urlString) {
                        Link(destination: url) {
                            Label("Open tracking", systemImage: "arrow.up.right.square")
                                .font(PerchTheme.Font.body)
                        }
                        .foregroundColor(PerchTheme.accent)
                    }

                } else if let event = record.asEvent() {
                    KeyValueList(rows: [
                        ("Start", event.start.formatted(date: .abbreviated, time: .shortened)),
                        ("End", event.end.formatted(date: .abbreviated, time: .shortened)),
                        ("Location", event.location ?? "—")
                    ])

                    if let notes = event.agentNotes, !notes.isEmpty {
                        Text(notes)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textSecondary)
                            .padding(PerchTheme.Spacing.medium)
                            .background(PerchTheme.cardBackground)
                            .cornerRadius(PerchTheme.Card.innerCornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                                    .stroke(PerchTheme.border, lineWidth: 1)
                            )
                    }

                } else if let bookmark = record.asBookmark() {
                    KeyValueList(rows: [
                        ("Domain", bookmark.domain ?? "—"),
                        ("Status", bookmark.status.rawValue.capitalized),
                        ("Reading time", bookmark.readingTimeMinutes.map { "\($0) min" } ?? "—")
                    ])

                    if let summary = bookmark.summary, !summary.isEmpty {
                        Text(summary)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textSecondary)
                            .padding(PerchTheme.Spacing.medium)
                            .background(PerchTheme.cardBackground)
                            .cornerRadius(PerchTheme.Card.innerCornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                                    .stroke(PerchTheme.border, lineWidth: 1)
                            )
                    }

                    if let url = URL(string: bookmark.url) {
                        Link(destination: url) {
                            Label("Open link", systemImage: "safari")
                                .font(PerchTheme.Font.body)
                        }
                        .foregroundColor(PerchTheme.accent)
                    }

                } else if let checklist = record.asChecklist() {
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                        ForEach(Array(checklist.items.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: PerchTheme.Spacing.small) {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(item.done ? PerchTheme.success : PerchTheme.textTertiary)
                                Text(item.text)
                                    .font(PerchTheme.Font.body)
                                    .foregroundColor(PerchTheme.textSecondary)
                                    .strikethrough(item.done, color: PerchTheme.textTertiary)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(PerchTheme.Spacing.medium)
                    .background(PerchTheme.cardBackground)
                    .cornerRadius(PerchTheme.Card.innerCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                            .stroke(PerchTheme.border, lineWidth: 1)
                    )

                } else if let cost = record.asCostSummary() {
                    KeyValueList(rows: [
                        ("Period", cost.period.capitalized),
                        ("Total", String(format: "$%.2f", cost.totalCostUsd))
                    ])

                } else {
                    KeyValueList(rows: [
                        ("Type", record.type.rawValue),
                        ("Category", record.category.rawValue),
                        ("Agent", record.agentId),
                        ("Updated", record.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    ])
                }
            }
        }
    }

    private var rawJSONSection: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            Text("Raw")
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textPrimary)

            VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                Text("data")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)

                MonospaceJSONView(text: prettyJSON(for: record.data) ?? "{}")

                if let annotations = record.annotations {
                    Text("annotations")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textSecondary)
                        .padding(.top, PerchTheme.Spacing.medium)

                    MonospaceJSONView(text: prettyJSON(for: annotations) ?? "{}")
                }
            }
        }
    }

    // MARK: - Formatting helpers

    private func formattedNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func prettyJSON(for value: JSONValue) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Small components

private struct KeyValueList: View {
    let rows: [(key: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.key)
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                        .frame(width: 90, alignment: .leading)

                    Text(row.value)
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textSecondary)

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(PerchTheme.Spacing.medium)
        .background(PerchTheme.cardBackground)
        .cornerRadius(PerchTheme.Card.innerCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                .stroke(PerchTheme.border, lineWidth: 1)
        )
    }
}

private struct MonospaceJSONView: View {
    let text: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(PerchTheme.textSecondary)
                .textSelection(.enabled)
                .padding(PerchTheme.Spacing.medium)
        }
        .background(PerchTheme.cardBackground)
        .cornerRadius(PerchTheme.Card.innerCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                .stroke(PerchTheme.border, lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        RecordDetailView(record: MockData.bookmarkRecords[0])
    }
    .background(PerchTheme.background)
}
