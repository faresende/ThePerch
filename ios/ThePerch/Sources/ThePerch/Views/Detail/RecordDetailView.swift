import SwiftUI

/// Rich in-app detail screen for any Record.
///
/// Detects the record type and shows an appropriate detailed view:
/// - Deliveries: tracking timeline, carrier info, tappable tracking number
/// - Events: full info, location link, add-to-calendar button
/// - Bookmarks: summary, tags, image preview, source badge
/// - Other types: key-value details with raw JSON
struct RecordDetailView: View {
    let record: Record

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
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
                    deliveryDetailView(delivery)

                } else if let event = record.asEvent() {
                    eventDetailView(event)

                } else if let bookmark = record.asBookmark() {
                    bookmarkDetailView(bookmark)

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

    // MARK: - Delivery Detail

    @ViewBuilder
    private func deliveryDetailView(_ delivery: DeliveryData) -> some View {
        // ETA prominently displayed
        if let eta = delivery.eta {
            HStack(spacing: PerchTheme.Spacing.small) {
                Image(systemName: "calendar.badge.clock")
                    .font(PerchTheme.Font.title)
                    .foregroundColor(PerchTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated Delivery")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                    Text(eta.formatted(date: .complete, time: .shortened))
                        .font(PerchTheme.Font.heading)
                        .foregroundColor(PerchTheme.textPrimary)
                }
                Spacer()
            }
            .padding(PerchTheme.Spacing.medium)
            .background(PerchTheme.accent.opacity(0.08))
            .cornerRadius(PerchTheme.Card.innerCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                    .stroke(PerchTheme.accent.opacity(0.3), lineWidth: 1)
            )
        }

        // Carrier & tracking info
        KeyValueList(rows: [
            ("Carrier", delivery.carrier),
            ("Status", delivery.status.replacingOccurrences(of: "_", with: " ").capitalized),
            ("Order ID", delivery.orderId)
        ])

        // Tracking number — tappable to copy
        Button {
            UIPasteboard.general.string = delivery.trackingNumber
            PerchHaptics.success()
        } label: {
            HStack(spacing: PerchTheme.Spacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tracking Number")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                    Text(delivery.trackingNumber)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(PerchTheme.textPrimary)
                }
                Spacer()
                Image(systemName: "doc.on.doc")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.accent)
            }
            .padding(PerchTheme.Spacing.medium)
            .background(PerchTheme.cardBackground)
            .cornerRadius(PerchTheme.Card.innerCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                    .stroke(PerchTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)

        // Items list
        if !delivery.items.isEmpty {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                Text("Items")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)

                ForEach(Array(delivery.items.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.name)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)
                        Spacer()
                        if item.quantity > 1 {
                            Text("x\(item.quantity)")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                    }
                    if let desc = item.description, !desc.isEmpty {
                        Text(desc)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
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

        // Tracking link
        if let urlString = delivery.trackingUrl, let url = URL(string: urlString) {
            Link(destination: url) {
                HStack {
                    Image(systemName: "safari")
                        .font(PerchTheme.Font.body)
                    Text("Track on \(delivery.carrier)")
                        .font(PerchTheme.Font.body)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(PerchTheme.Font.caption)
                }
                .foregroundColor(.white)
                .padding(PerchTheme.Spacing.medium)
                .background(PerchTheme.accent)
                .cornerRadius(PerchTheme.Card.innerCornerRadius)
            }
        }
    }

    // MARK: - Event Detail

    @ViewBuilder
    private func eventDetailView(_ event: EventData) -> some View {
        // Title & time
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
            Text(event.title)
                .font(PerchTheme.Font.title)
                .foregroundColor(PerchTheme.textPrimary)

            // Duration
            let duration = event.end.timeIntervalSince(event.start)
            let durationMinutes = Int(duration / 60)
            let hours = durationMinutes / 60
            let mins = durationMinutes % 60
            let durationText = hours > 0
                ? (mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h")
                : "\(mins)m"

            HStack(spacing: PerchTheme.Spacing.small) {
                Image(systemName: "clock")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
                Text(durationText)
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textSecondary)
            }
        }

        KeyValueList(rows: [
            ("Start", event.start.formatted(date: .complete, time: .shortened)),
            ("End", event.end.formatted(date: .abbreviated, time: .shortened))
        ])

        // Location — tappable to open Maps
        if let location = event.location, !location.isEmpty {
            Button {
                let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? location
                if let url = URL(string: "maps://?q=\(encoded)") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: PerchTheme.Spacing.small) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.accent)
                    Text(location)
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }
                .padding(PerchTheme.Spacing.medium)
                .background(PerchTheme.cardBackground)
                .cornerRadius(PerchTheme.Card.innerCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                        .stroke(PerchTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }

        // Notes/description
        if let notes = event.agentNotes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                Text("Notes")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
                Text(notes)
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textSecondary)
            }
            .padding(PerchTheme.Spacing.medium)
            .background(PerchTheme.cardBackground)
            .cornerRadius(PerchTheme.Card.innerCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                    .stroke(PerchTheme.border, lineWidth: 1)
            )
        }

        // Add to Calendar button
        Button {
            let interval = event.start.timeIntervalSinceReferenceDate
            if let url = URL(string: "calshow:\(interval)") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack {
                Image(systemName: "calendar.badge.plus")
                    .font(PerchTheme.Font.body)
                Text("Open in Calendar")
                    .font(PerchTheme.Font.body)
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(PerchTheme.Font.caption)
            }
            .foregroundColor(.white)
            .padding(PerchTheme.Spacing.medium)
            .background(PerchTheme.accent)
            .cornerRadius(PerchTheme.Card.innerCornerRadius)
        }
    }

    // MARK: - Bookmark Detail

    @ViewBuilder
    private func bookmarkDetailView(_ bookmark: BookmarkData) -> some View {
        // Source badge + reading time
        HStack(spacing: PerchTheme.Spacing.small) {
            // Source badge
            let source = bookmark.source ?? .karakeep
            Text(source == .paperless ? "Paperless" : "Karakeep")
                .font(PerchTheme.Font.caption)
                .fontWeight(.medium)
                .foregroundColor(source == .paperless ? PerchTheme.warning : PerchTheme.accent)
                .padding(.horizontal, PerchTheme.Spacing.small)
                .padding(.vertical, PerchTheme.Spacing.xxSmall)
                .background(
                    (source == .paperless ? PerchTheme.warning : PerchTheme.accent).opacity(0.12)
                )
                .cornerRadius(4)

            if let readingTime = bookmark.readingTimeMinutes {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(PerchTheme.Font.micro)
                    Text("\(readingTime) min read")
                        .font(PerchTheme.Font.caption)
                }
                .foregroundColor(PerchTheme.textTertiary)
            }

            Spacer()

            Text(bookmark.status.rawValue.capitalized)
                .font(PerchTheme.Font.caption)
                .foregroundColor(bookmark.status == .processed ? PerchTheme.success : PerchTheme.textTertiary)
        }

        // Image preview
        if let imageUrlString = bookmark.imageUrl, let imageUrl = URL(string: imageUrlString) {
            AsyncImage(url: imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxHeight: 200)
                        .clipped()
                        .cornerRadius(PerchTheme.Card.innerCornerRadius)
                default:
                    EmptyView()
                }
            }
        }

        // Key info
        KeyValueList(rows: [
            ("Domain", bookmark.domain ?? "—"),
            ("Title", bookmark.displayTitle)
        ])

        // Summary
        if let summary = bookmark.summary, !summary.isEmpty {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                Text("Summary")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
                Text(summary)
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textSecondary)
            }
            .padding(PerchTheme.Spacing.medium)
            .background(PerchTheme.cardBackground)
            .cornerRadius(PerchTheme.Card.innerCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                    .stroke(PerchTheme.border, lineWidth: 1)
            )
        }

        // Tags as chips
        if !bookmark.tags.isEmpty {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                Text("Tags")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)

                FlowLayout(spacing: PerchTheme.Spacing.xSmall) {
                    ForEach(bookmark.tags, id: \.self) { tag in
                        Text(tag)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.accent)
                            .padding(.horizontal, PerchTheme.Spacing.small)
                            .padding(.vertical, PerchTheme.Spacing.xxSmall)
                            .background(PerchTheme.accent.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
        }

        // Open in Safari button
        if let url = URL(string: bookmark.url) {
            Link(destination: url) {
                HStack {
                    Image(systemName: "safari")
                        .font(PerchTheme.Font.body)
                    Text("Open in Safari")
                        .font(PerchTheme.Font.body)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(PerchTheme.Font.caption)
                }
                .foregroundColor(.white)
                .padding(PerchTheme.Spacing.medium)
                .background(PerchTheme.accent)
                .cornerRadius(PerchTheme.Card.innerCornerRadius)
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
        PerchFormatters.decimal.string(from: NSNumber(value: value)) ?? String(value)
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

// MARK: - Flow Layout for tag chips

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}

#Preview {
    NavigationStack {
        RecordDetailView(record: MockData.bookmarkRecords[0])
    }
    .background(PerchTheme.background)
}
