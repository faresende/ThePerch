import SwiftUI

/// Calendar section showing upcoming events with the new EventCard design.
/// Reads records from DashboardViewModel (single-fetch architecture).
struct CalendarView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var cardsAppeared = false

    private var records: [Record] { dashboardViewModel.calendarRecords }

    /// Single-pass decode: partition into today vs. upcoming, sort both by start time.
    private var categorizedEvents: (today: [Record], upcoming: [Record]) {
        let calendar = Calendar.current
        var today: [(Record, Date)] = []
        var upcoming: [(Record, Date)] = []
        for record in records {
            guard let event = record.asEvent() else { continue }
            if calendar.isDateInToday(event.start) {
                today.append((record, event.start))
            } else if event.start > Date.now {
                upcoming.append((record, event.start))
            }
        }
        today.sort { $0.1 < $1.1 }
        upcoming.sort { $0.1 < $1.1 }
        return (today.map(\.0), upcoming.map(\.0))
    }

    var todayEvents: [Record] { categorizedEvents.today }
    var upcomingEvents: [Record] { categorizedEvents.upcoming }

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            if dashboardViewModel.isLoading && records.isEmpty {
                SkeletonCalendarSection()
                    .padding(.horizontal, PerchTheme.Spacing.large)
                    .padding(.top, 60)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    // Section header with freshness
                    SectionHeader(title: "Calendar", freshnessKey: "calendar")
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.top, PerchTheme.Spacing.medium)

                    // Error banner
                    if dashboardViewModel.error != nil {
                        ErrorBanner(
                            message: "Failed to load calendar events",
                            retryAction: { Task { await dashboardViewModel.refreshRecords() } },
                            onDismiss: { dashboardViewModel.clearError() }
                        )
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    // Today's events
                    if !todayEvents.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Today")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            VStack(spacing: PerchTheme.Spacing.medium) {
                                ForEach(Array(todayEvents.enumerated()), id: \.element.id) { index, record in
                                    if let eventData = record.asEvent() {
                                        EventCard(event: eventData)
                                            .cardAppear(index: index, appeared: cardsAppeared)
                                    }
                                }
                            }
                            .onAppear {
                                PerchMotion.withOptionalAnimation { cardsAppeared = true }
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    // Upcoming events
                    if !upcomingEvents.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Upcoming")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            VStack(spacing: PerchTheme.Spacing.small) {
                                ForEach(Array(upcomingEvents.enumerated()), id: \.element.id) { index, record in
                                    if let eventData = record.asEvent() {
                                        UpcomingEventRow(event: eventData)
                                            .cardAppear(index: index + todayEvents.count, appeared: cardsAppeared)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    if todayEvents.isEmpty && upcomingEvents.isEmpty {
                        emptyStateView
                    }

                    Spacer()
                        .frame(height: PerchTheme.Spacing.large)
                }
            }
            .refreshable {
                PerchHaptics.medium()
                await dashboardViewModel.refreshRecords()
                PerchHaptics.success()
            }
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            Image(systemName: "calendar")
                .font(PerchTheme.Font.icon(PerchTheme.Icon.xxLarge))
                .foregroundColor(PerchTheme.textTertiary)

            VStack(spacing: PerchTheme.Spacing.xSmall) {
                Text("No events")
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                Text("Your calendar events will appear here")
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(PerchTheme.Spacing.large)
    }
}

// MARK: - Upcoming Event Row

/// Compact row for upcoming (non-today) events with date, time, title, and location.
struct UpcomingEventRow: View {
    let event: EventData

    private var dayLabel: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(event.start) {
            return "Today"
        } else if calendar.isDateInTomorrow(event.start) {
            return "Tomorrow"
        } else {
            return PerchFormatters.shortDate.string(from: event.start)
        }
    }

    var body: some View {
        Button(action: openInCalendar) {
            HStack(spacing: PerchTheme.Spacing.small) {
                // Date badge
                VStack(spacing: 2) {
                    Text(dayLabel)
                        .font(PerchTheme.Font.micro)
                        .fontWeight(.semibold)
                        .foregroundColor(PerchTheme.accent)

                    Text(event.start.formatted(date: .omitted, time: .shortened))
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textPrimary)
                }
                .frame(width: 60)

                // Left accent line
                RoundedRectangle(cornerRadius: 1)
                    .fill(PerchTheme.border)
                    .frame(width: 2, height: 36)

                // Event info
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textPrimary)
                        .lineLimit(1)

                    if let location = event.location {
                        Text(location)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
            }
            .padding(.horizontal, PerchTheme.Spacing.medium)
            .padding(.vertical, PerchTheme.Spacing.small)
            .background(PerchTheme.cardBackground)
            .cornerRadius(PerchTheme.Card.cornerRadius)
        }
        .buttonStyle(CardPressStyle())
    }

    private func openInCalendar() {
        let interval = event.start.timeIntervalSinceReferenceDate
        if let url = URL(string: "calshow:\(interval)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Preview

#Preview {
    CalendarView()
        .environment(DashboardViewModel())
}
