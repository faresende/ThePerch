import SwiftUI

// MARK: - ParseTraceSheet
//
// Long-press peek that explains "why was this classified as an order?"
// Renders the `parse_trace` JSONB column from public.orders in a
// human-readable form. Phase 1 corrections-and-rules debug surface;
// Phase 2 will reuse this for showing rule-promotion candidates and
// Phase 3 for LLM-fallback reasoning.
//
// Renders pragmatically: the trace's shape can evolve on the scanner
// side (see scanner_version field), so we walk the JSON tree
// dynamically rather than requiring an exact Swift mirror. New fields
// the scanner adds will surface automatically as "Other" rows; iOS
// doesn't need a release.

struct ParseTraceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.perchPalette) private var palette

    let orderId: UUID
    let orderMerchant: String

    @State private var trace: [String: Any]?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                PerchTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                        kicker
                        if isLoading {
                            loadingState
                        } else if let error {
                            errorState(error)
                        } else if let trace {
                            traceBody(trace)
                        } else {
                            emptyState
                        }
                    }
                    .padding(PerchTheme.Spacing.large)
                }
            }
            .navigationTitle("Why this is an order?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadTrace()
            }
        }
    }

    // MARK: - Sections

    private var kicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PARSE TRACE")
                .font(PerchTheme.Font.cardEyebrow)
                .foregroundColor(palette.muted)
                .textCase(.uppercase)
            Text(orderMerchant)
                .font(PerchTheme.Font.heading)
                .foregroundColor(palette.ink)
        }
    }

    private var loadingState: some View {
        HStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .padding(.vertical, 24)
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Couldn't load parse trace")
                .font(PerchTheme.Font.caption.weight(.semibold))
                .foregroundColor(palette.error)
            Text(message)
                .font(PerchTheme.Font.caption)
                .foregroundColor(palette.muted)
        }
    }

    private var emptyState: some View {
        Text("No parse trace — this order was created before parse traces were captured.")
            .font(PerchTheme.Font.caption)
            .foregroundColor(palette.muted)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private func traceBody(_ trace: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            // Top-line: parsed_at + scanner_version
            metadataRow(trace)

            if let classifier = trace["classifier"] as? [String: Any] {
                section(title: "Classifier") {
                    classifierRows(classifier)
                }
            }

            if let merchant = trace["merchant"] as? [String: Any] {
                section(title: "Merchant") {
                    merchantRows(merchant)
                }
            }

            if let pd = trace["physical_vs_digital"] as? [String: Any] {
                section(title: "Physical vs digital") {
                    physicalDigitalRows(pd)
                }
            }

            if let candidates = trace["tracking_candidates"] as? [[String: Any]],
               !candidates.isEmpty {
                section(title: "Tracking candidates") {
                    trackingCandidateRows(candidates)
                }
            }

            if let emailIds = trace["source_email_ids"] as? [String], !emailIds.isEmpty {
                section(title: "Source emails") {
                    sourceEmailRows(emailIds)
                }
            }
        }
    }

    // MARK: - Row builders

    private func metadataRow(_ trace: [String: Any]) -> some View {
        HStack(spacing: 8) {
            if let parsedAt = trace["parsed_at"] as? String {
                Text(parsedAt.prefix(19).replacingOccurrences(of: "T", with: " "))
            }
            if let scanner = trace["scanner_version"] as? String {
                Text("·").foregroundColor(palette.faint)
                Text(scanner)
            }
        }
        .font(PerchTheme.Font.microNumeric)
        .foregroundColor(palette.muted)
    }

    @ViewBuilder
    private func classifierRows(_ classifier: [String: Any]) -> some View {
        if let tier1 = classifier["tier1"] as? [String: Any] {
            kvRow("Tier 1 keywords",
                  value: (tier1["matched_keywords"] as? [String])?.joined(separator: ", ") ?? "—",
                  trailing: confidenceLabel(tier1["confidence"]))
        }
        if let llm = classifier["llm"] as? [String: Any], (llm["invoked"] as? Bool) == true {
            kvRow("LLM",
                  value: llmDescription(llm),
                  trailing: confidenceLabel(llm["confidence"]))
        }
        if let learned = classifier["learned_sender"] as? [String: Any], (learned["matched"] as? Bool) == true {
            kvRow("Learned sender",
                  value: (learned["merchant"] as? String) ?? "matched",
                  trailing: (learned["match_axis"] as? String) ?? "")
        }
        if let shortCircuit = classifier["short_circuited_by"] as? String {
            kvRow("Short-circuited by", value: shortCircuit, trailing: "")
        }
        if let ruleId = classifier["merchant_rule_applied"] as? String {
            kvRow("Merchant rule applied", value: ruleId, trailing: "")
        }
        if (classifier["low_confidence_flagged"] as? Bool) == true {
            kvRow("Low-confidence flag",
                  value: "tier1 + LLM both <0.5 — Phase 3 fallback eligible",
                  trailing: "")
        }
    }

    @ViewBuilder
    private func merchantRows(_ merchant: [String: Any]) -> some View {
        kvRow("Selected", value: (merchant["selected"] as? String) ?? "—",
              trailing: (merchant["source"] as? String) ?? "")
        if let candidates = merchant["candidates"] as? [String], candidates.count > 1 {
            kvRow("Candidates", value: candidates.joined(separator: ", "), trailing: "")
        }
    }

    @ViewBuilder
    private func physicalDigitalRows(_ pd: [String: Any]) -> some View {
        kvRow("Decision", value: (pd["decision"] as? String) ?? "—", trailing: "")
        if let signals = pd["signals"] as? [String: Any] {
            if let phrases = signals["digital_phrases_found"] as? [String], !phrases.isEmpty {
                kvRow("Digital phrases", value: phrases.joined(separator: ", "), trailing: "")
            }
            if let kws = signals["tangible_keywords"] as? [String], !kws.isEmpty {
                kvRow("Tangible keywords", value: kws.joined(separator: ", "), trailing: "")
            }
            if let addr = signals["shipping_address_in_body"] as? Bool {
                kvRow("Shipping address in body", value: addr ? "yes" : "no", trailing: "")
            }
        }
    }

    @ViewBuilder
    private func trackingCandidateRows(_ candidates: [[String: Any]]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(candidates.enumerated()), id: \.offset) { _, c in
                let selected = (c["selected"] as? Bool) ?? false
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selected ? palette.wellness : palette.faint)
                        .font(.system(size: 14))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text((c["number"] as? String) ?? "—")
                                .font(PerchTheme.Font.microNumeric)
                                .foregroundColor(palette.ink)
                            if let carrier = c["carrier"] as? String {
                                Text("·").foregroundColor(palette.faint)
                                Text(carrier)
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(palette.muted)
                            }
                        }
                        Text(candidateSubtitle(c))
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(palette.faint)
                    }
                }
            }
        }
    }

    private func candidateSubtitle(_ c: [String: Any]) -> String {
        let source = (c["source"] as? String) ?? "unknown source"
        if let reason = c["discarded_reason"] as? String {
            return "\(source) · \(reason)"
        }
        return source
    }

    @ViewBuilder
    private func sourceEmailRows(_ emailIds: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(emailIds, id: \.self) { id in
                Text(id)
                    .font(PerchTheme.Font.microNumeric)
                    .foregroundColor(palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Reusable bits

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(PerchTheme.Font.cardEyebrow)
                .foregroundColor(palette.muted)
                .textCase(.uppercase)
            content()
        }
        .padding(PerchTheme.Spacing.medium)
        .background(palette.chipBg)
        .cornerRadius(PerchTheme.Card.innerCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                .stroke(palette.line.opacity(0.5), lineWidth: 1)
        )
    }

    private func kvRow(_ key: String, value: String, trailing: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key)
                .font(PerchTheme.Font.caption)
                .foregroundColor(palette.muted)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(PerchTheme.Font.caption)
                .foregroundColor(palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(PerchTheme.Font.microNumeric)
                    .foregroundColor(palette.faint)
            }
        }
    }

    private func confidenceLabel(_ raw: Any?) -> String {
        guard let n = raw as? Double else {
            if let i = raw as? Int { return String(format: "%.2f", Double(i)) }
            return ""
        }
        return String(format: "%.2f", n)
    }

    private func llmDescription(_ llm: [String: Any]) -> String {
        let isPurchase = llm["is_purchase"] as? Bool
        let provider = (llm["provider"] as? String) ?? "?"
        switch isPurchase {
        case true:  return "purchase confirmed (\(provider))"
        case false: return "not a purchase (\(provider))"
        default:    return "invoked (\(provider))"
        }
    }

    // MARK: - Loader

    private func loadTrace() async {
        do {
            let fetched = try await OrdersService.shared.fetchParseTrace(orderId: orderId)
            self.trace = fetched
            self.isLoading = false
        } catch {
            self.error = error.localizedDescription
            self.isLoading = false
        }
    }
}
