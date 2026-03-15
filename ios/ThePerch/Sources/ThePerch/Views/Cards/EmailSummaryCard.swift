import SwiftUI

/// Shows top 3 urgent/flagged emails with sender, subject, and time ago.
/// Tapping an email opens Fastmail. Hides when no important emails exist.
struct EmailSummaryCard: View {
    let records: [Record]

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
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                // Header
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    Image(systemName: "envelope.fill")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.accent)
                    Text("IMPORTANT EMAILS")
                        .font(PerchTheme.Font.cardEyebrow)
                        .foregroundColor(PerchTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Spacer()
                    CardFreshnessLabel(date: emailRecord?.updatedAt)
                    if let unread = summary.totalUnread, unread > 0 {
                        Text("\(unread) unread")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textTertiary)
                    }
                }

                // Top 3 emails
                ForEach(Array(summary.emails.prefix(3))) { email in
                    emailRow(email: email)
                }

                // Footer: view all
                if let unread = summary.totalUnread, unread > summary.emails.prefix(3).count {
                    Button {
                        openFastmail()
                    } label: {
                        Text("View all \(unread) unread")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(PerchTheme.Card.padding)
            .cardStyle()
        }
    }

    // MARK: - Email Row

    private func emailRow(email: EmailSummaryData.EmailItem) -> some View {
        Button {
            openFastmailSearch(sender: email.sender, subject: email.subject)
        } label: {
            HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
                // Flag/urgent indicator
                if email.isFlagged {
                    Image(systemName: "star.fill")
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(PerchTheme.warning)
                        .frame(width: 14)
                } else if email.isUrgent {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(PerchTheme.error)
                        .frame(width: 14)
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Sender
                    Text(email.sender)
                        .font(PerchTheme.Font.body)
                        .fontWeight(.medium)
                        .foregroundColor(PerchTheme.textPrimary)
                        .lineLimit(1)
                    // Subject
                    Text(email.subject)
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Time ago
                Text(relativeTime(from: email.receivedAt))
                    .font(PerchTheme.Font.micro)
                    .foregroundColor(PerchTheme.textTertiary)
            }
            .padding(.horizontal, PerchTheme.Spacing.small)
            .padding(.vertical, PerchTheme.Spacing.xSmall)
            .background(PerchTheme.cardInnerBackground)
            .cornerRadius(PerchTheme.Card.innerCornerRadius)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func relativeTime(from isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString)
                ?? ISO8601DateFormatter().date(from: isoString) else {
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
            UIApplication.shared.open(url)
        }
    }

    private func openFastmail() {
        if let url = URL(string: "https://app.fastmail.com/mail/") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Preview

#Preview {
    EmailSummaryCard(records: [])
        .padding(PerchTheme.Spacing.large)
        .background(PerchTheme.background)
}
