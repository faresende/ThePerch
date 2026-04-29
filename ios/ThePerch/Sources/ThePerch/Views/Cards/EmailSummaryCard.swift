import SwiftUI

/// Shows top 3 urgent/flagged emails with sender, subject, and time ago.
/// Tapping an email opens Fastmail. Hides when no important emails exist.
struct EmailSummaryCard: View {
    let records: [Record]
    @Environment(\.perchPalette) private var palette

    private var emailRecord: Record? {
        records.first { record in
            record.category == .admin &&
            record.title.localizedCaseInsensitiveContains("email")
        }
    }

    private var emailSummary: EmailSummaryData? {
        records.compactMap { record -> EmailSummaryData? in
            guard record.category == .admin,
                  record.title.localizedCaseInsensitiveContains("email")
            else { return nil }
            return record.asEmailSummary()
        }.first
    }

    var body: some View {
        if let summary = emailSummary, !summary.emails.isEmpty {
            let top = Array(summary.emails.prefix(3))
            TodayCard {
                VStack(alignment: .leading, spacing: 0) {
                    TodayEyebrow(
                        label: "EMAIL · WORTH A LOOK",
                        accent: palette.wellness,
                        freshness: freshnessText
                    )
                    TodayPhrase(text: PerchPhrase.emailPhrase(threadCount: top.count))

                    VStack(spacing: 0) {
                        ForEach(Array(top.enumerated()), id: \.element.id) { index, email in
                            if index > 0 {
                                Rectangle()
                                    .fill(palette.line)
                                    .frame(height: 1)
                            }
                            emailRow(email: email)
                        }
                    }

                    // View-all footer (when unread exceeds displayed)
                    if let unread = summary.totalUnread, unread > top.count {
                        Button { openFastmail() } label: {
                            Text("View all \(unread) unread")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(palette.kinetic)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                    }
                }
            }
        }
    }

    private var freshnessText: String {
        guard let date = emailRecord?.updatedAt else { return "—" }
        let minutes = Int(Date.now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) hr"
    }

    // MARK: - Email Row (Linen spec — priority rail, from, subject, age)

    private func emailRow(email: EmailSummaryData.EmailItem) -> some View {
        let isHighPriority = email.isFlagged || email.isUrgent
        return Button {
            openFastmailSearch(sender: email.sender, subject: email.subject)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // 4pt vertical priority rail — kinetic for high, line for low
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isHighPriority ? palette.kinetic : palette.line)
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 1) {
                    Text(email.sender)
                        .font(.system(size: 12.5))
                        .foregroundColor(palette.muted)
                        .lineLimit(1)
                    Text(email.subject)
                        .font(PerchTheme.Font.bodyRow)
                        .foregroundColor(palette.ink)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(relativeTime(from: email.receivedAt))
                    .font(PerchTheme.Font.microNumeric)
                    .tracking(0.2)
                    .foregroundColor(palette.faint)
                    .padding(.top, 2)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func relativeTime(from isoString: String) -> String {
        // Reuse the shared formatters — was allocating two
        // ISO8601DateFormatter instances per email-row render.
        guard let date = PerchFormatters.iso8601Fractional.date(from: isoString)
                ?? PerchFormatters.iso8601.date(from: isoString) else {
            return ""
        }
        let interval = Date.now.timeIntervalSince(date)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        if hours < 24 { return "\(hours)h" }
        return "\(days)d"
    }

    private func openFastmailSearch(sender: String, subject: String) {
        // Try Fastmail app deep link, fallback to web
        if let url = URL(string: "https://app.fastmail.com/mail/") {
            ExternalURLOpener.openExternal(url)
        }
    }

    private func openFastmail() {
        if let url = URL(string: "https://app.fastmail.com/mail/") {
            ExternalURLOpener.openExternal(url)
        }
    }
}

// MARK: - Preview

#Preview {
    EmailSummaryCard(records: [])
        .padding(PerchTheme.Spacing.large)
        .background(PerchTheme.background)
}
