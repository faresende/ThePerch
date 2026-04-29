import SwiftUI

/// Shows a daily medication checklist with interactive checkboxes.
/// Tapping a checkbox toggles the isChecked state via Supabase mutation.
/// When all medications are taken, collapses to a compact "All taken" row.
struct MedicationsCard: View {
    let records: [Record]

    @State private var isMutating = false
    @Environment(\.perchPalette) private var palette

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
            let takenCount = meds.items.filter(\.isChecked).count
            let totalCount = meds.items.count

            TodayCard {
                VStack(alignment: .leading, spacing: 0) {
                    TodayEyebrow(
                        label: "MEDS · TODAY",
                        accent: palette.wellness,
                        freshness: "\(takenCount)/\(totalCount)"
                    )
                    TodayPhrase(text: PerchPhrase.medsPhrase(taken: takenCount, total: totalCount))

                    VStack(spacing: 0) {
                        ForEach(Array(meds.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Rectangle()
                                    .fill(palette.line)
                                    .frame(height: 1)
                            }
                            medicationRow(item: item)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Medication Row (Linen spec — checkbox, name · dose, when)

    private func medicationRow(item: MedicationChecklistData.MedicationItem) -> some View {
        Button {
            guard !isMutating else { return }
            toggleMedication(item)
        } label: {
            HStack(spacing: 10) {
                // Checkbox — 18×18, 9pt radius, wellness when taken
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(item.isChecked ? palette.wellness : .clear)
                        .frame(width: 18, height: 18)
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(item.isChecked ? .clear : palette.line, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if item.isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(palette.heroText)
                    }
                }

                // Name · dose
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(PerchTheme.Font.bodyRow)
                        .foregroundColor(item.isChecked ? palette.muted : palette.ink)
                        .strikethrough(item.isChecked, color: palette.faint)
                    if let schedule = item.schedule {
                        Text("· \(schedule)")
                            .font(.system(size: 12))
                            .foregroundColor(palette.faint)
                    }
                }

                Spacer()

                // When (right-side, serif)
                // The schedule text in data already covers this in some cases;
                // leave blank for now to avoid duplication.
            }
            .padding(.vertical, 8)
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
                #if DEBUG
                print("[MedicationsCard] Toggle failed: \(error)")
                #endif
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
