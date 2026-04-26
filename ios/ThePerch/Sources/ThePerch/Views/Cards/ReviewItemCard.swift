import SwiftUI

/// A single row in the review queue — a `review_items` record the
/// autopilot wasn't confident about. Used by both the Hub's inline
/// review section and the dedicated OrdersView's review section so
/// the visual treatment stays in lock-step across surfaces.
///
/// Collapsed state shows the merchant guess + subject + sender + the
/// two action buttons. Tap anywhere on the card to toggle expanded
/// state — that reveals the autopilot's reasoning, its best-guess
/// fields, and (if we have a JMAP id) a deep-link to Fastmail to read
/// the source email. Expansion uses the same workout-card pattern as
/// OrderCard: parent owns `expandedReviewId`, only one card open at a
/// time, spring animation `.spring(response: 0.3, dampingFraction: 0.7)`.
struct ReviewItemCard: View {
    @Environment(\.perchPalette) private var palette

    let item: ReviewItem
    let isExpanded: Bool
    let isResolving: Bool
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        PerchSectionCard(padding: 14) {
            // ─── Header: merchant kicker + freshness + chevron ────────
            HStack(alignment: .firstTextBaseline) {
                Text(item.displayMerchant.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(relativeTime)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.faint)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.faint)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }

            // ─── Subject (serif italic, 2 lines collapsed / unlimited expanded) ───
            Text(item.displaySubject)
                .font(.system(size: 14, weight: .regular, design: .serif).italic())
                .foregroundStyle(palette.ink)
                .lineLimit(isExpanded ? nil : 2)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // ─── Sender mono ───────────────────────────────────────────
            if let s = item.sourceSenderEmail, !s.isEmpty {
                Text(s)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.faint)
                    .lineLimit(isExpanded ? nil : 1)
                    .truncationMode(.middle)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // ─── Expanded section: WHY + best-guess fields + Fastmail link ───
            if isExpanded {
                Divider()
                    .background(palette.line.opacity(0.5))
                    .padding(.top, 10)

                expandedDetails
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ─── Action row ────────────────────────────────────────────
            HStack(spacing: 8) {
                Spacer()
                if isResolving {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(palette.kinetic)
                } else {
                    Button(action: onDismiss) {
                        Text("Not an order")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(palette.line.opacity(0.5))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss \(item.displayMerchant)")

                    Button(action: onConfirm) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Add as order")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(palette.kinetic)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(item.displayMerchant) as order")
                }
            }
            .padding(.top, 8)
        }
        // Whole card is the tap target. Outer Button wrapper in the
        // parent (HubReviewQueueSection / ReviewQueueSection) handles
        // toggle. The inner action buttons opt out by being `.plain`
        // styled buttons — SwiftUI defers to the inner button when the
        // tap lands on its content shape.
        .contentShape(Rectangle())
    }

    // MARK: - Expanded content

    @ViewBuilder
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            // WHY — the autopilot's reasoning string
            if !item.reason.isEmpty && item.reason != item.displaySubject {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WHY")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(palette.faint)
                    Text(item.reason)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // BEST GUESS — what the autopilot would create if confirmed
            if hasSuggestedFields {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AUTOPILOT'S BEST GUESS")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(palette.faint)

                    if let m = item.suggestedMerchant, !m.isEmpty {
                        labeledRow("Merchant", m)
                    }
                    if let n = item.suggestedOrderNumber, !n.isEmpty {
                        labeledRow("Order #", n)
                    }
                    if let total = item.suggestedTotalAmount {
                        labeledRow("Total", formatCurrency(total, code: item.suggestedCurrency ?? "USD"))
                    }
                }
            }

            // Source email deep-link — Fastmail web URL
            if let eid = item.sourceEmailId,
               !eid.isEmpty,
               let url = fastmailURL(for: eid) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "envelope")
                            .font(.system(size: 11, weight: .medium))
                        Text("Open in Fastmail")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(palette.kinetic)
                }
            }
        }
    }

    private var hasSuggestedFields: Bool {
        (item.suggestedMerchant?.isEmpty == false)
            || (item.suggestedOrderNumber?.isEmpty == false)
            || item.suggestedTotalAmount != nil
    }

    @ViewBuilder
    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(palette.faint)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fastmailURL(for emailId: String) -> URL? {
        // Fastmail's web inbox accepts JMAP email IDs prefixed with
        // a dot. Tested against `https://app.fastmail.com/mail/Inbox/.<id>`.
        URL(string: "https://app.fastmail.com/mail/Inbox/.\(emailId)")
    }

    private func formatCurrency(_ amount: Decimal, code: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = code
        return f.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }

    private var relativeTime: String {
        let interval = Date.now.timeIntervalSince(item.createdAt)
        let m = Int(interval / 60)
        if m < 1 { return "just now" }
        if m < 60 { return "\(m)m ago" }
        let h = m / 60
        if h < 24 { return "\(h)h ago" }
        return "\(h / 24)d ago"
    }
}
