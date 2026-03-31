import SwiftUI

/// Calendar section showing upcoming events with the new EventCard design.
/// Reads records from DashboardViewModel (single-fetch architecture).
struct CalendarView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var cardsAppeared = false
    @State private var selectedDate = CalendarView.dayCalendar.startOfDay(for: .now)

    private static let dayCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    private static let weekCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    private static let selectedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    fileprivate static let upcomingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()

    private static let timezoneFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm z"
        return formatter
    }()

    private var records: [Record] { dashboardViewModel.calendarRecords }

    private var events: [EventData] {
        records
            .compactMap { record in record.asEvent() }
            .sorted { lhs, rhs in lhs.start < rhs.start }
    }

    private var travelTrips: [TripData] {
        dashboardViewModel.travelRecords
            .compactMap { record in record.asTrip() }
            .sorted { lhs, rhs in
                (lhs.startDateParsed ?? .distantFuture) < (rhs.startDateParsed ?? .distantFuture)
            }
    }

    private var currentTrip: TripData? {
        travelTrips.first(where: { $0.status == "active" })
        ?? travelTrips.first(where: { $0.status == "upcoming" })
    }

    private var selectedDayEvents: [EventData] {
        events.filter { event in
            Self.dayCalendar.isDate(event.start, equalTo: selectedDate, toGranularity: .day)
        }
    }

    private var upcomingEvents: [EventData] {
        Array(events.filter { $0.start > Date.now }.prefix(7))
    }

    private var selectedDayTitle: String {
        let formattedDate = Self.selectedDateFormatter.string(from: selectedDate)
        if Self.dayCalendar.isDateInToday(selectedDate) {
            return "Today — \(formattedDate)"
        }
        return formattedDate
    }

    private var weekDates: [Date] {
        let components = Self.weekCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
        guard let startOfWeek = Self.weekCalendar.date(from: components) else { return [] }
        return (0..<7).compactMap { offset in
            Self.weekCalendar.date(byAdding: .day, value: offset, to: startOfWeek)
        }
    }

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    SectionHeader(title: "Calendar", freshnessKey: "calendar")
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.top, PerchTheme.Spacing.medium)

                    if dashboardViewModel.error != nil {
                        ErrorBanner(
                            message: "Failed to load calendar events",
                            retryAction: { Task { await dashboardViewModel.loadDashboard(forceRefresh: true) } },
                            onDismiss: { dashboardViewModel.clearError() }
                        )
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    if dashboardViewModel.isLoading && records.isEmpty {
                        SkeletonCardsSection(count: 3)
                            .padding(.horizontal, PerchTheme.Spacing.large)
                    } else {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            dayNavigationHeader
                            weekOverview

                            if selectedDayEvents.isEmpty {
                                EmptyStateView(
                                    icon: "calendar",
                                    title: "No events"
                                )
                                .background(PerchTheme.cardBackground)
                                .cornerRadius(PerchTheme.Card.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                                        .stroke(PerchTheme.border, lineWidth: PerchTheme.Card.borderWidth)
                                )
                            } else {
                                VStack(spacing: PerchTheme.Spacing.medium) {
                                    ForEach(Array(selectedDayEvents.enumerated()), id: \.offset) { index, event in
                                        EventCard(event: event, timezoneText: timezoneText(for: event))
                                            .cardAppear(index: index, appeared: cardsAppeared)
                                    }
                                }
                                .onAppear {
                                    PerchMotion.withOptionalAnimation { cardsAppeared = true }
                                }
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)

                        if !upcomingEvents.isEmpty {
                            VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                                Text("UPCOMING")
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(PerchTheme.textSecondary)
                                    .tracking(1)

                                VStack(spacing: PerchTheme.Spacing.small) {
                                    ForEach(Array(upcomingEvents.enumerated()), id: \.offset) { index, event in
                                        UpcomingEventRow(event: event, timezoneText: timezoneText(for: event))
                                            .cardAppear(index: index + selectedDayEvents.count, appeared: cardsAppeared)
                                    }
                                }
                            }
                            .padding(.horizontal, PerchTheme.Spacing.large)
                        }
                    }

                    Spacer()
                        .frame(height: PerchTheme.Spacing.large)
                }
            }
            .refreshable {
                PerchHaptics.medium()
                await dashboardViewModel.loadDashboard(forceRefresh: true)
                PerchHaptics.success()
            }
        }
    }

    private var dayNavigationHeader: some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            Button(action: { shiftSelectedDate(by: -1) }) {
                Image(systemName: "chevron.left")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(PerchTheme.cardInnerBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text(selectedDayTitle)
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textPrimary)
                .frame(maxWidth: .infinity)

            Button(action: { shiftSelectedDate(by: 1) }) {
                Image(systemName: "chevron.right")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(PerchTheme.cardInnerBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var weekOverview: some View {
        HStack(spacing: PerchTheme.Spacing.xSmall) {
            ForEach(weekDates, id: \.self) { date in
                let isSelected = Self.dayCalendar.isDate(date, inSameDayAs: selectedDate)
                let isToday = Self.dayCalendar.isDateInToday(date)
                let hasEvents = dayHasEvents(date)

                Button(action: { selectDate(date) }) {
                    VStack(spacing: 6) {
                        Text(Self.weekdayFormatter.string(from: date).uppercased())
                            .font(PerchTheme.Font.micro)
                            .foregroundColor(isToday ? PerchTheme.accentForeground : PerchTheme.textTertiary)

                        Text("\(Self.dayCalendar.component(.day, from: date))")
                            .font(PerchTheme.Font.bodyNumeric)
                            .foregroundColor(isToday ? PerchTheme.accentForeground : PerchTheme.textPrimary)

                        Circle()
                            .fill(hasEvents ? (isToday ? PerchTheme.accentForeground : PerchTheme.accent) : Color.clear)
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PerchTheme.Spacing.small)
                    .background(pillBackground(isToday: isToday, isSelected: isSelected))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(pillBorder(isToday: isToday, isSelected: isSelected), lineWidth: isSelected && !isToday ? 1.5 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shiftSelectedDate(by days: Int) {
        guard let newDate = Self.dayCalendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        selectDate(newDate)
    }

    private func selectDate(_ date: Date) {
        PerchMotion.withOptionalAnimation {
            selectedDate = Self.dayCalendar.startOfDay(for: date)
        }
    }

    private func dayHasEvents(_ date: Date) -> Bool {
        events.contains { event in
            Self.dayCalendar.isDate(event.start, equalTo: date, toGranularity: .day)
        }
    }

    private func pillBackground(isToday: Bool, isSelected: Bool) -> Color {
        if isToday {
            return PerchTheme.accent
        }
        if isSelected {
            return PerchTheme.cardBackground
        }
        return PerchTheme.cardInnerBackground
    }

    private func pillBorder(isToday: Bool, isSelected: Bool) -> Color {
        if isToday {
            return PerchTheme.accent
        }
        if isSelected {
            return PerchTheme.accent.opacity(0.35)
        }
        return PerchTheme.border
    }

    private func timezoneText(for event: EventData) -> String? {
        if let locationTimeZone = inferredTimeZone(from: event.location),
           locationTimeZone.identifier != TimeZone.current.identifier {
            return timezoneSummary(for: event, in: locationTimeZone, prefix: "Local time")
        }

        guard let trip = relevantTrip(for: event),
              let destinationId = trip.destinationTz,
              let destinationTimeZone = TimeZone(identifier: destinationId),
              destinationId != TimeZone.current.identifier else {
            return nil
        }

        let destinationLabel = trip.destination.isEmpty ? "Destination time" : "\(trip.destination) time"
        return timezoneSummary(for: event, in: destinationTimeZone, prefix: destinationLabel)
    }

    private func relevantTrip(for event: EventData) -> TripData? {
        travelTrips.first { trip in
            guard let start = trip.startDateParsed,
                  let end = trip.endDateParsed,
                  let origin = trip.originTz,
                  let destination = trip.destinationTz,
                  origin != destination else {
                return false
            }

            let day = Self.dayCalendar.startOfDay(for: event.start)
            let tripStart = Self.dayCalendar.startOfDay(for: start)
            let tripEnd = Self.dayCalendar.startOfDay(for: end)
            return day >= tripStart && day <= tripEnd
        } ?? {
            guard let trip = currentTrip,
                  trip.status == "active",
                  let origin = trip.originTz,
                  let destination = trip.destinationTz,
                  origin != destination else {
                return nil
            }
            return trip
        }()
    }

    private func timezoneSummary(for event: EventData, in timeZone: TimeZone, prefix: String) -> String {
        Self.timezoneFormatter.timeZone = timeZone
        let localLabel = Self.timezoneFormatter.string(from: event.start)
        let diffHours = (timeZone.secondsFromGMT(for: event.start) - TimeZone.current.secondsFromGMT(for: event.start)) / 3600

        guard diffHours != 0 else {
            return "\(prefix) · \(localLabel)"
        }

        let sign = diffHours > 0 ? "+" : ""
        return "\(prefix) · \(localLabel) (\(sign)\(diffHours)h)"
    }

    private func inferredTimeZone(from location: String?) -> TimeZone? {
        guard let location,
              !location.isEmpty else { return nil }

        let tokens = location
            .uppercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for token in tokens {
            if let identifier = TimeZone.abbreviationDictionary[token],
               let timeZone = TimeZone(identifier: identifier) {
                return timeZone
            }
        }

        if let match = TimeZone.knownTimeZoneIdentifiers.first(where: { location.localizedCaseInsensitiveContains($0) }) {
            return TimeZone(identifier: match)
        }

        return nil
    }
}

// MARK: - Upcoming Event Row

/// Compact row for upcoming (non-today) events with date, time, title, and location.
struct UpcomingEventRow: View {
    let event: EventData
    let timezoneText: String?

    private var dayLabel: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(event.start) {
            return "Today"
        } else if calendar.isDateInTomorrow(event.start) {
            return "Tomorrow"
        } else {
            return CalendarView.upcomingDateFormatter.string(from: event.start)
        }
    }

    var body: some View {
        Button(action: openInCalendar) {
            HStack(spacing: PerchTheme.Spacing.small) {
                VStack(spacing: 2) {
                    Text(dayLabel)
                        .font(PerchTheme.Font.micro)
                        .fontWeight(.semibold)
                        .foregroundColor(PerchTheme.accent)

                    Text(event.start.formatted(date: .omitted, time: .shortened))
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textPrimary)
                }
                .frame(width: 76)

                RoundedRectangle(cornerRadius: 1)
                    .fill(PerchTheme.border)
                    .frame(width: 2, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let location = event.location, !location.isEmpty {
                        Text(location)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textTertiary)
                            .lineLimit(1)
                    }

                    if let timezoneText, !timezoneText.isEmpty {
                        Label(timezoneText, systemImage: "globe")
                            .font(PerchTheme.Font.micro)
                            .foregroundColor(PerchTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
