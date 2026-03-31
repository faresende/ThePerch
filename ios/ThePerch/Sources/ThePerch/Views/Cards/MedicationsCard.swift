import SwiftUI

/// Shows a daily medication checklist with interactive checkboxes.
/// Tapping a checkbox toggles the isChecked state via Supabase mutation.
/// When all medications are taken, collapses to a compact "All taken" row.
struct MedicationsCard: View {
    let records: [Record]

    @State private var isMutating = false

    private var medicationRecord: Record? {
        records.first { record in
            record.type == .checklist
            && record.category == .health
            && record.title.localizedCaseInsensitiveContains("medication")
        }
    }

    private var medications: MedicationChecklistData? {
        medicationRecord?.asMedications()
    }

    var body: some View {
        if let meds = medications {
            let allChecked = meds.items.allSatisfy(\.isChecked)

            VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                // Header
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    Image(systemName: "pill.fill")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.accent)
                    Text("MEDICATIONS")
                        .font(PerchTheme.Font.cardEyebrow)
                        .foregroundColor(PerchTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Spacer()
                    CardFreshnessLabel(date: medicationRecord?.updatedAt)
                    if allChecked {
                        Text("All taken")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.success)
                    }
                }

                if allChecked {
                    // Compact: all done
                    HStack(spacing: PerchTheme.Spacing.xSmall) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(PerchTheme.success)
                        Text("All medications taken")
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                } else {
                    // Checklist items
                    ForEach(meds.items) { item in
                        medicationRow(item: item)
                    }
                }
            }
            .padding(PerchTheme.Card.padding)
            .cardStyle()
        }
    }

    // MARK: - Medication Row

    private func medicationRow(item: MedicationChecklistData.MedicationItem) -> some View {
        Button {
            guard !isMutating else { return }
            toggleMedication(item)
        } label: {
            HStack(spacing: PerchTheme.Spacing.small) {
                // Checkbox
                ZStack {
                    if item.isChecked {
                        Circle()
                            .fill(PerchTheme.accent)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(PerchTheme.Font.caption)
                            .fontWeight(.bold)
                            .foregroundColor(PerchTheme.accentForeground)
                    } else {
                        Circle()
                            .strokeBorder(PerchTheme.textTertiary, lineWidth: 2)
                            .frame(width: 24, height: 24)
                    }
                }

                // Name
                Text(item.name)
                    .font(PerchTheme.Font.body)
                    .foregroundColor(item.isChecked ? PerchTheme.textTertiary : PerchTheme.textPrimary)
                    .strikethrough(item.isChecked, color: PerchTheme.textTertiary)

                Spacer()

                // Schedule note
                if let schedule = item.schedule {
                    Text(schedule)
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }

                if item.isChecked {
                    Text("done")
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(PerchTheme.success)
                }
            }
            .padding(.horizontal, PerchTheme.Spacing.medium)
            .padding(.vertical, PerchTheme.Spacing.small)
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

    // MARK: - Mutation

    private func toggleMedication(_ item: MedicationChecklistData.MedicationItem) {
        guard let record = medicationRecord, let meds = medications else { return }

        // Haptic: success for checking, light for unchecking
        if !item.isChecked {
            PerchHaptics.success()
        } else {
            PerchHaptics.light()
        }
        isMutating = true

        // Build updated items list
        let updatedItems: [JSONValue] = meds.items.map { med in
            let checked = med.id == item.id ? !med.isChecked : med.isChecked
            var obj: [String: JSONValue] = [
                "id": .string(med.id),
                "name": .string(med.name),
                "is_checked": .bool(checked)
            ]
            if let schedule = med.schedule {
                obj["schedule"] = .string(schedule)
            }
            return .object(obj)
        }

        let updatedData: [String: JSONValue] = ["items": .array(updatedItems)]

        Task { @MainActor in
            defer { isMutating = false }
            do {
                try await SupabaseService.shared.updateRecordData(
                    recordId: record.id,
                    data: updatedData
                )
            } catch {
                PerchHaptics.error()
                print("[MedicationsCard] Toggle failed: \(error)")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MedicationsCard(records: [])
        .padding(PerchTheme.Spacing.large)
        .background(PerchTheme.background)
}
