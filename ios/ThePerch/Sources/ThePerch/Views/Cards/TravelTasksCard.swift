import SwiftUI

/// Pre-trip checklist card shown above the itinerary timeline.
struct TravelTasksCard: View {
    let tasks: [(Record, TravelTaskData)]
    @State private var mutatingIds: Set<UUID> = []

    private var doneCount: Int { tasks.filter(\.1.done).count }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
            // Header
            HStack {
                Text("TRIP PREP")
                    .font(PerchTheme.Font.cardEyebrow)
                    .foregroundColor(PerchTheme.textSecondary)
                    .tracking(0.8)

                Spacer()

                Text("\(doneCount)/\(tasks.count)")
                    .font(PerchTheme.Font.captionNumeric)
                    .foregroundColor(doneCount == tasks.count ? PerchTheme.success : PerchTheme.accent)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(PerchTheme.border)
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(doneCount == tasks.count ? PerchTheme.success : PerchTheme.accent)
                        .frame(width: tasks.isEmpty ? 0 : geo.size.width * CGFloat(doneCount) / CGFloat(tasks.count), height: 3)
                }
            }
            .frame(height: 3)

            // Task items
            ForEach(tasks, id: \.0.id) { record, task in
                taskRow(record: record, task: task)
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }

    @ViewBuilder
    private func taskRow(record: Record, task: TravelTaskData) -> some View {
        let isMutating = mutatingIds.contains(record.id)

        Button {
            toggleTask(record: record, task: task)
        } label: {
            HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(PerchTheme.Font.body)
                    .foregroundColor(task.done ? PerchTheme.success : PerchTheme.textTertiary)
                    .opacity(isMutating ? 0.5 : 1.0)

                Text(task.task)
                    .font(PerchTheme.Font.body)
                    .foregroundColor(task.done ? PerchTheme.textTertiary : PerchTheme.textPrimary)
                    .strikethrough(task.done, color: PerchTheme.textTertiary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isMutating)
    }

    private func toggleTask(record: Record, task: TravelTaskData) {
        if !task.done {
            PerchHaptics.success()
        } else {
            PerchHaptics.light()
        }

        mutatingIds.insert(record.id)

        let updatedData: [String: JSONValue] = [
            "trip_id": .string(task.tripId),
            "task": .string(task.task),
            "done": .bool(!task.done)
        ]

        // Preserve optional date
        var fullData = updatedData
        if let date = task.date {
            fullData["date"] = .string(date)
        }

        Task { @MainActor in
            defer { mutatingIds.remove(record.id) }
            do {
                try await SupabaseService.shared.updateRecordData(
                    recordId: record.id,
                    data: fullData
                )
            } catch {
                PerchHaptics.error()
                print("[TravelTasksCard] Toggle failed: \(error)")
            }
        }
    }
}

/// Compact inline task row for use within the timeline.
struct InlineTaskRow: View {
    let record: Record
    let task: TravelTaskData
    @State private var isMutating = false

    var body: some View {
        Button {
            toggleTask()
        } label: {
            HStack(spacing: PerchTheme.Spacing.small) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(task.done ? PerchTheme.success : PerchTheme.textTertiary)

                Text(task.task)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(task.done ? PerchTheme.textTertiary : PerchTheme.textPrimary)
                    .strikethrough(task.done, color: PerchTheme.textTertiary)
                    .lineLimit(2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isMutating)
    }

    private func toggleTask() {
        if !task.done {
            PerchHaptics.success()
        } else {
            PerchHaptics.light()
        }

        isMutating = true

        var fullData: [String: JSONValue] = [
            "trip_id": .string(task.tripId),
            "task": .string(task.task),
            "done": .bool(!task.done)
        ]
        if let date = task.date {
            fullData["date"] = .string(date)
        }

        Task { @MainActor in
            defer { isMutating = false }
            do {
                try await SupabaseService.shared.updateRecordData(
                    recordId: record.id,
                    data: fullData
                )
            } catch {
                PerchHaptics.error()
                print("[InlineTaskRow] Toggle failed: \(error)")
            }
        }
    }
}
