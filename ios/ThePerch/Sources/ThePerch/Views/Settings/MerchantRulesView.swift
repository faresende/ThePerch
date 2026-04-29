// MerchantRulesView.swift
//
// Settings → Auto-learned rules. Lists every public.merchant_rules
// row owned by the user. Each row is toggleable + swipe-to-delete.
// Auto-promoted rules show their correction count + a "promoted from
// N corrections" footnote so the user can sanity-check why a rule
// landed in the table.

import SwiftUI

struct MerchantRulesView: View {
    @Environment(\.perchPalette) private var palette

    @State private var rules: [MerchantRule] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var pendingMutation: UUID?

    var body: some View {
        Group {
            if isLoading && rules.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                ContentUnavailableView(
                    "Couldn't load rules",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
            } else if rules.isEmpty {
                emptyState
            } else {
                ruleList
            }
        }
        .navigationTitle("Auto-learned rules")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(forceRefresh: false) }
        .refreshable { await load(forceRefresh: true) }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView(
            "No rules yet",
            systemImage: "wand.and.stars",
            description: Text(
                "When you mark the same sender as 'Not an order' three times "
                + "in 60 days, a rule lands here automatically and future "
                + "emails from that sender skip the orders pipeline."
            )
        )
    }

    @ViewBuilder
    private var ruleList: some View {
        List {
            SwiftUI.Section {
                ForEach(rules) { rule in
                    ruleRow(rule)
                }
                .onDelete(perform: deleteAt)
            } footer: {
                Text(
                    "Disabled rules stay listed for history but no longer "
                    + "block emails. Swipe left to delete a rule entirely — "
                    + "the autopilot will start classifying that sender again."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func ruleRow(_ rule: MerchantRule) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(rule.displayMatch)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { rule.enabled },
                    set: { newValue in toggleRule(rule, to: newValue) }
                ))
                .labelsHidden()
                .disabled(pendingMutation == rule.id)
            }

            HStack(spacing: 8) {
                Text(rule.displayAction.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(rule.sourceLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(palette.muted)
                if let n = rule.promotedFromCorrectionCount, rule.source == "auto_promoted" {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("\(n) corrections")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if let notes = rule.notes, !notes.isEmpty {
                Text(notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .opacity(rule.enabled ? 1.0 : 0.55)
    }

    // MARK: - Actions

    private func load(forceRefresh: Bool = false) async {
        loadError = nil
        do {
            let fetched = try await MerchantRulesService.shared.fetchRules(forceRefresh: forceRefresh)
            rules = fetched
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleRule(_ rule: MerchantRule, to newValue: Bool) {
        pendingMutation = rule.id
        Task {
            defer { pendingMutation = nil }
            do {
                try await MerchantRulesService.shared.setEnabled(rule.id, enabled: newValue)
                // Optimistic local update — avoids a full reload flicker.
                if let i = rules.firstIndex(where: { $0.id == rule.id }) {
                    let copy = rules[i]
                    rules[i] = MerchantRule(
                        id: copy.id, userId: copy.userId,
                        matchKind: copy.matchKind, matchValue: copy.matchValue,
                        action: copy.action, source: copy.source,
                        promotedFromCorrectionCount: copy.promotedFromCorrectionCount,
                        notes: copy.notes, enabled: newValue,
                        createdAt: copy.createdAt, updatedAt: Date()
                    )
                }
            } catch {
                loadError = error.localizedDescription
                await load()  // reconcile against server truth
            }
        }
    }

    private func deleteAt(_ offsets: IndexSet) {
        let toDelete = offsets.map { rules[$0] }
        // Optimistic remove
        rules.remove(atOffsets: offsets)
        Task {
            for rule in toDelete {
                do {
                    try await MerchantRulesService.shared.deleteRule(rule.id)
                } catch {
                    loadError = error.localizedDescription
                    await load()  // reconcile
                    return
                }
            }
        }
    }
}
