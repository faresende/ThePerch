import SwiftUI

/// "Next workout" suggestion card. Reads the latest `workout_hint`
/// record — BioChecha writes one per day after reviewing recent training.
struct WorkoutHintCard: View {
    let record: Record?

    private var data: WorkoutHintData? {
        record?.decodeData(as: WorkoutHintData.self)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
            HStack(spacing: 8) {
                Text("Next workout")
                    .font(PerchTheme.Font.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("BioChecha")
                    .font(PerchTheme.Font.caption)
                    .foregroundStyle(.secondary)
            }

            if let data {
                HStack(spacing: 12) {
                    Image(systemName: symbol(for: data.suggestedType))
                        .font(PerchTheme.Font.icon(32))
                        .foregroundStyle(color(for: data.suggestedType))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label(for: data.suggestedType))
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(PerchTheme.textPrimary)
                        if let reasoning = data.reasoning, !reasoning.isEmpty {
                            Text(reasoning)
                                .font(PerchTheme.Font.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let flags = data.flags, !flags.isEmpty {
                    Divider().padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(flags) { f in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "dot.circle")
                                    .font(PerchTheme.Font.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                                Text(f.detail)
                                    .font(PerchTheme.Font.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            } else {
                Text("No training hint yet for today.")
                    .font(PerchTheme.Font.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PerchTheme.Spacing.medium)
        .cardStyle()
    }

    private func symbol(for t: WorkoutHintData.SuggestedType) -> String {
        switch t {
        case .pull:  return "figure.strengthtraining.functional"
        case .push:  return "figure.strengthtraining.traditional"
        case .legs:  return "figure.run"
        case .rest:  return "moon.zzz.fill"
        case .mixed: return "figure.cross.training"
        case .other: return "figure.mixed.cardio"
        }
    }

    private func color(for t: WorkoutHintData.SuggestedType) -> Color {
        switch t {
        case .pull:  return .blue
        case .push:  return .orange
        case .legs:  return .green
        case .rest:  return .purple
        case .mixed: return .teal
        case .other: return .secondary
        }
    }

    private func label(for t: WorkoutHintData.SuggestedType) -> String {
        switch t {
        case .pull:  return "Pull day"
        case .push:  return "Push day"
        case .legs:  return "Legs day"
        case .rest:  return "Rest day"
        case .mixed: return "Mixed"
        case .other: return "Other"
        }
    }
}

#if DEBUG
#Preview {
    WorkoutHintCard(record: nil)
        .padding()
        .background(PerchTheme.background)
}
#endif
