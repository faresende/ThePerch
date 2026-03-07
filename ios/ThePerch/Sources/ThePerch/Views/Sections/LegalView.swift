import SwiftUI

/// Legal section showing checklists and document tracking.
struct LegalView: View {
    @State private var viewModel = SectionViewModel(category: .legal)

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            if viewModel.isLoading && viewModel.records.isEmpty {
                VStack(spacing: PerchTheme.Spacing.medium) {
                    SkeletonRect(height: 200, cornerRadius: PerchTheme.Card.cornerRadius)
                }
                .padding(.horizontal, PerchTheme.Spacing.large)
                .padding(.top, 60)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    // Section header with freshness
                    SectionHeader(title: "Legal", freshnessKey: "legal")
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.top, PerchTheme.Spacing.medium)

                    // Checklists
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                        Text("Document Checklists")
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(PerchTheme.textPrimary)

                        VStack(spacing: PerchTheme.Spacing.medium) {
                            ForEach(viewModel.records) { record in
                                if let checklistData = record.asChecklist() {
                                    ChecklistCard(
                                        title: record.title,
                                        items: checklistData.items
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, PerchTheme.Spacing.large)

                    if viewModel.records.isEmpty && !viewModel.isLoading {
                        emptyStateView
                    }

                    Spacer()
                        .frame(height: PerchTheme.Spacing.large)
                }
            }
            .refreshable {
                PerchHaptics.medium()
                await viewModel.refresh()
                PerchHaptics.success()
            }
        }
        .task {
            await viewModel.loadRecords()
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            Image(systemName: "doc.text")
                .font(PerchTheme.Font.icon(PerchTheme.Icon.xxLarge))
                .foregroundColor(PerchTheme.textTertiary)

            VStack(spacing: PerchTheme.Spacing.xSmall) {
                Text("No documents")
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                Text("Legal documents and checklists will appear here")
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(PerchTheme.Spacing.large)
    }
}

// MARK: - Preview

#Preview {
    LegalView()
}
