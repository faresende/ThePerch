import SwiftUI

/// Travel section showing trip itinerary timeline, alerts, and weather.
/// Data is fed from DashboardViewModel (single-fetch architecture).
struct TravelView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var viewModel = TravelViewModel()
    @State private var selectedTripId: String?
    @State private var cardsAppeared = false

    /// The trip to display: selected, or current, or most recent past.
    private var displayTrip: (Record, TripData)? {
        if let id = selectedTripId {
            return viewModel.trips.first { $0.1.tripId == id }
        }
        return viewModel.currentTrip ?? viewModel.pastTrips.first
    }

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    // Section header
                    SectionHeader(title: "Travel", freshnessKey: "travel")
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.top, PerchTheme.Spacing.medium)

                    if viewModel.trips.isEmpty {
                        emptyState
                    } else {
                        // Trip selector (if multiple trips)
                        if viewModel.trips.count > 1 {
                            tripSelector
                                .padding(.horizontal, PerchTheme.Spacing.large)
                        }

                        if let (_, trip) = displayTrip {
                            // Trip header card
                            tripHeaderCard(trip: trip)
                                .cardAppear(index: 0, appeared: cardsAppeared)
                                .padding(.horizontal, PerchTheme.Spacing.large)

                            // Alerts
                            let alerts = viewModel.alerts(for: trip.tripId)
                            if !alerts.isEmpty {
                                alertsSection(alerts: alerts)
                                    .cardAppear(index: 1, appeared: cardsAppeared)
                                    .padding(.horizontal, PerchTheme.Spacing.large)
                            }

                            // Itinerary timeline
                            itineraryTimeline(tripId: trip.tripId)
                                .cardAppear(index: 2, appeared: cardsAppeared)
                                .padding(.horizontal, PerchTheme.Spacing.large)

                            let tripEvents = calendarEvents(for: trip)
                            if !tripEvents.isEmpty {
                                calendarSection(events: tripEvents, trip: trip)
                                    .cardAppear(index: 3, appeared: cardsAppeared)
                                    .padding(.horizontal, PerchTheme.Spacing.large)
                            }

                            // Weather
                            let forecasts = viewModel.weatherForecasts(for: trip.tripId)
                            if !forecasts.isEmpty {
                                weatherSection(forecasts: forecasts)
                                    .cardAppear(index: 4, appeared: cardsAppeared)
                                    .padding(.horizontal, PerchTheme.Spacing.large)
                            }
                        }
                    }

                    Spacer().frame(height: PerchTheme.Spacing.large)
                }
            }
            .refreshable {
                PerchHaptics.medium()
                await dashboardViewModel.refreshRecords()
                PerchHaptics.success()
            }
        }
        .onChange(of: dashboardViewModel.travelRecords) { _, new in
            viewModel.records = new
        }
        .onAppear {
            if !dashboardViewModel.travelRecords.isEmpty {
                viewModel.records = dashboardViewModel.travelRecords
            }
            PerchMotion.withOptionalAnimation { cardsAppeared = true }
        }
    }

    // MARK: - Trip Selector

    private var tripSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PerchTheme.Spacing.small) {
                ForEach(viewModel.trips, id: \.1.tripId) { _, trip in
                    let isSelected = (selectedTripId ?? viewModel.currentTrip?.1.tripId) == trip.tripId
                    Button {
                        selectedTripId = trip.tripId
                        PerchHaptics.light()
                    } label: {
                        HStack(spacing: 4) {
                            Text(statusEmoji(trip.status))
                            Text(trip.destination)
                                .font(PerchTheme.Font.caption)
                        }
                        .foregroundColor(isSelected ? PerchTheme.background : PerchTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isSelected ? PerchTheme.accent : PerchTheme.cardInnerBackground)
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    // MARK: - Trip Header Card

    private func tripHeaderCard(trip: TripData) -> some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            // Destination + status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.destination)
                        .font(PerchTheme.Font.title)
                        .foregroundColor(PerchTheme.textPrimary)

                    HStack(spacing: PerchTheme.Spacing.xSmall) {
                        if let origin = trip.origin {
                            Text(origin)
                                .font(PerchTheme.Font.body)
                                .foregroundColor(PerchTheme.textTertiary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                        Text(trip.destination)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                }

                Spacer()

                // Status badge
                statusBadge(trip: trip)
            }

            // Date range
            if let start = trip.startDateParsed, let end = trip.endDateParsed {
                HStack(spacing: PerchTheme.Spacing.small) {
                    Image(systemName: "calendar")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                    Text("\(PerchFormatters.shortWeekdayDate.string(from: start)) – \(PerchFormatters.shortWeekdayDate.string(from: end))")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textSecondary)

                    if let total = trip.totalDays {
                        Text("· \(total) nights")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textTertiary)
                    }
                }
            }

            // Timezone info
            if let destTz = trip.destinationTz, let originTz = trip.originTz, destTz != originTz {
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    Image(systemName: "clock")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                    Text(formatTimezoneOffset(origin: originTz, destination: destTz))
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }
            }

            // Weather summary
            if let weather = viewModel.weatherSummary(for: trip.tripId) {
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    Text(weather.emoji)
                    Text("\(Int(weather.avgTemp))°C avg")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textSecondary)
                    Text("· \(weather.condition.replacingOccurrences(of: "_", with: " ").localizedCapitalized)")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }

    // MARK: - Alerts Section

    private func alertsSection(alerts: [(Record, TravelAlertData)]) -> some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
            ForEach(alerts, id: \.0.id) { _, alert in
                HStack(spacing: PerchTheme.Spacing.small) {
                    Image(systemName: alert.isCritical ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(alert.isCritical ? PerchTheme.error : PerchTheme.warning)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.message)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)

                        if let flight = alert.flightNumber {
                            Text(flight)
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                    }

                    Spacer()
                }
                .padding(PerchTheme.Spacing.medium)
                .background(
                    (alert.isCritical ? PerchTheme.error : PerchTheme.warning).opacity(0.1)
                )
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Timeline Entry (virtual, supports hotel split)

    /// A virtual timeline entry that may represent a full segment or one half of a hotel stay.
    private struct TimelineEntry: Identifiable {
        let id: String
        let record: Record
        let segment: ItineraryData
        let hotelMode: HotelMode
        let sortDate: Date

        enum HotelMode {
            case notHotel       // Normal segment
            case checkIn        // Hotel check-in card
            case checkOut       // Hotel check-out card
        }
    }

    // MARK: - Itinerary Timeline

    private func itineraryTimeline(tripId: String) -> some View {
        let segments = viewModel.segments(for: tripId)

        // Build virtual entries, splitting hotels into check-in + check-out
        var entries: [TimelineEntry] = []
        for (record, segment) in segments {
            if segment.isHotel {
                // Check-in: uses departure date (that's how data is structured)
                if let checkInDate = segment.departure {
                    entries.append(TimelineEntry(
                        id: "\(record.id.uuidString)-checkin",
                        record: record,
                        segment: segment,
                        hotelMode: .checkIn,
                        sortDate: checkInDate
                    ))
                }
                // Check-out: uses arrival date
                if let checkOutDate = segment.arrival {
                    entries.append(TimelineEntry(
                        id: "\(record.id.uuidString)-checkout",
                        record: record,
                        segment: segment,
                        hotelMode: .checkOut,
                        sortDate: checkOutDate
                    ))
                }
            } else {
                let date = segment.departure ?? segment.checkIn ?? record.createdAt
                entries.append(TimelineEntry(
                    id: record.id.uuidString,
                    record: record,
                    segment: segment,
                    hotelMode: .notHotel,
                    sortDate: date
                ))
            }
        }

        entries.sort { $0.sortDate < $1.sortDate }

        // Group by day
        let grouped = Dictionary(grouping: entries) { entry -> String in
            PerchFormatters.shortWeekdayDate.string(from: entry.sortDate)
        }
        let sortedDays = grouped.keys.sorted { k1, k2 in
            let d1 = grouped[k1]!.first?.sortDate ?? .distantFuture
            let d2 = grouped[k2]!.first?.sortDate ?? .distantFuture
            return d1 < d2
        }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sortedDays.enumerated()), id: \.element) { dayIndex, dayLabel in
                // Day header
                HStack(spacing: PerchTheme.Spacing.small) {
                    Text(dayLabel)
                        .font(PerchTheme.Font.heading)
                        .foregroundColor(PerchTheme.textPrimary)
                    Spacer()
                }
                .padding(.vertical, PerchTheme.Spacing.small)
                .padding(.horizontal, PerchTheme.Spacing.small)

                // Entries for this day
                let dayEntries = grouped[dayLabel]!
                ForEach(dayEntries) { entry in
                    HStack(alignment: .top, spacing: PerchTheme.Spacing.medium) {
                        // Timeline line + dot
                        VStack(spacing: 0) {
                            Circle()
                                .fill(segmentStatusColor(entry.segment))
                                .frame(width: 10, height: 10)

                            if dayEntries.last?.id != entry.id || dayIndex < sortedDays.count - 1 {
                                Rectangle()
                                    .fill(PerchTheme.border)
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 20)

                        // Segment content
                        segmentCard(record: entry.record, segment: entry.segment, hotelMode: entry.hotelMode)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, PerchTheme.Spacing.small)
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }

    // MARK: - Segment Type Tag

    private func segmentTypeTag(_ segment: ItineraryData) -> some View {
        let (emoji, label) = segmentTagInfo(segment)
        return Text("\(emoji) \(label)")
            .font(PerchTheme.Font.micro)
            .foregroundColor(PerchTheme.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(PerchTheme.cardInnerBackground)
            .cornerRadius(4)
    }

    private func segmentTagInfo(_ segment: ItineraryData) -> (String, String) {
        switch segment.segmentType {
        case "flight": return ("✈️", "Flight")
        case "hotel": return ("🏨", "Hotel")
        case "train": return ("🚂", "Train")
        case "car_rental": return ("🚗", "Rental")
        case "drive": return ("🚗", "Drive")
        case "restaurant": return ("🍽", "Restaurant")
        default: return ("📍", segment.segmentType.capitalized)
        }
    }

    // MARK: - Segment Card

    /// Strip leading emoji characters from a title (the timeline icon already conveys type).
    private func cleanTitle(_ title: String) -> String {
        var s = title
        // Strip leading emoji + whitespace
        while let first = s.first, first.unicodeScalars.allSatisfy({ $0.properties.isEmoji && !$0.isASCII }) {
            s.removeFirst()
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Format a confirmation/reference code for display (group long digit strings).
    private func formatConfirmation(_ conf: String) -> String {
        // Short alphanumeric codes (like PNRs): show as-is
        if conf.count <= 8 { return conf }
        // Long numeric strings: group into chunks of 4 for readability
        if conf.allSatisfy(\.isNumber) {
            var result = ""
            for (i, ch) in conf.enumerated() {
                if i > 0 && i % 4 == 0 { result += " " }
                result.append(ch)
            }
            return result
        }
        return conf
    }

    @ViewBuilder
    private func segmentCard(record: Record, segment: ItineraryData, hotelMode: TimelineEntry.HotelMode = .notHotel) -> some View {
        HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
            // Leading icon (fixed width, text wraps past it)
            Image(systemName: segmentIcon(segment))
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.accent)
                .frame(width: 18, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
            // Row 1: Name (full width, no status competing)
            if segment.isFlight {
                VStack(alignment: .leading, spacing: 2) {
                    Text(segment.flightLabel ?? "Flight")
                        .font(PerchTheme.Font.body)
                        .fontWeight(.semibold)
                        .foregroundColor(PerchTheme.textPrimary)

                    if let origin = segment.origin, let dest = segment.destination {
                        Text("\(origin) → \(dest)")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                }
            } else if segment.isHotel {
                VStack(alignment: .leading, spacing: 2) {
                    Text(segment.name ?? cleanTitle(record.title))
                        .font(PerchTheme.Font.body)
                        .fontWeight(.semibold)
                        .foregroundColor(PerchTheme.textPrimary)
                        .lineLimit(2)

                    if hotelMode == .checkIn {
                        Text("Check-in")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.accent)
                    } else if hotelMode == .checkOut {
                        Text("Check-out")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                }
            } else {
                Text(segment.name ?? cleanTitle(record.title))
                    .font(PerchTheme.Font.body)
                    .fontWeight(.semibold)
                    .foregroundColor(PerchTheme.textPrimary)
                    .lineLimit(2)
            }

            // Row 2: Time + status on the same line
            HStack {
                if segment.isHotel {
                    switch hotelMode {
                    case .checkIn:
                        if let dep = segment.departure {
                            Text(PerchFormatters.time24h.string(from: dep))
                                .font(PerchTheme.Font.captionNumeric)
                                .foregroundColor(PerchTheme.textSecondary)
                        }
                    case .checkOut:
                        if let arr = segment.arrival {
                            Text(PerchFormatters.time24h.string(from: arr))
                                .font(PerchTheme.Font.captionNumeric)
                                .foregroundColor(PerchTheme.textSecondary)
                        }
                    case .notHotel:
                        if let dep = segment.departure {
                            Text(PerchFormatters.time24h.string(from: dep))
                                .font(PerchTheme.Font.captionNumeric)
                                .foregroundColor(PerchTheme.textSecondary)
                        }
                    }
                } else {
                    if let dep = segment.departure {
                        Label(PerchFormatters.time24h.string(from: dep), systemImage: "arrow.up.right")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                    if let arr = segment.arrival {
                        Label(PerchFormatters.time24h.string(from: arr), systemImage: "arrow.down.right")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                }

                Spacer()

                // Status: dot only for confirmed, dot + text for exceptional states
                if let status = segment.status {
                    let isNormal = status == "confirmed" || status == "on_time"
                    HStack(spacing: 4) {
                        Circle()
                            .fill(segmentStatusColor(segment))
                            .frame(width: 6, height: 6)
                        if !isNormal {
                            Text(status.replacingOccurrences(of: "_", with: " ").localizedCapitalized)
                                .font(PerchTheme.Font.micro)
                                .foregroundColor(segmentStatusColor(segment))
                        }
                    }
                }
            }

            // Row 3: Details (gate, seat, confirmation with label)
            let hasGate = segment.gate != nil
            let hasSeat = segment.seat != nil
            let hasConf = hotelMode != .checkOut && segment.confirmation != nil
            if hasGate || hasSeat || hasConf {
                HStack(spacing: PerchTheme.Spacing.medium) {
                    if let gate = segment.gate {
                        Text("Gate \(gate)")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.accent)
                    }
                    if let seat = segment.seat {
                        Text("Seat \(seat)")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textTertiary)
                    }
                    if hotelMode != .checkOut, let conf = segment.confirmation {
                        Text("Ref \(formatConfirmation(conf))")
                            .font(PerchTheme.Font.captionNumeric)
                            .foregroundColor(PerchTheme.textTertiary)
                            .onTapGesture {
                                UIPasteboard.general.string = conf
                                PerchHaptics.light()
                            }
                    }
                }
            }

            // Row 4: Address (check-in only for hotels)
            if hotelMode != .checkOut, let address = segment.address {
                Text(address)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
                    .lineLimit(1)
            }
            } // end inner VStack
        } // end HStack (icon + content)
        .padding(PerchTheme.Spacing.medium)
        .background(PerchTheme.cardInnerBackground)
        .cornerRadius(10)
        .padding(.bottom, PerchTheme.Spacing.small)
    }

    // MARK: - Weather Section

    @ViewBuilder
    private func weatherSection(forecasts: [(Record, WeatherForecastData)]) -> some View {
        let packingHints = uniquePackingHints(from: forecasts)

        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
            Text("WEATHER")
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textSecondary)
                .tracking(1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PerchTheme.Spacing.small) {
                    ForEach(forecasts, id: \.0.id) { _, forecast in
                        VStack(spacing: 6) {
                            Text(forecast.conditionEmoji)
                                .font(PerchTheme.Font.title)

                            if let high = forecast.tempHigh, let low = forecast.tempLow {
                                Text("\(Int(high))°/\(Int(low))°")
                                    .font(PerchTheme.Font.captionNumeric)
                                    .foregroundColor(PerchTheme.textPrimary)
                            } else if let avg = forecast.tempAvg {
                                Text("\(Int(avg))°C")
                                    .font(PerchTheme.Font.captionNumeric)
                                    .foregroundColor(PerchTheme.textPrimary)
                            }

                            Text(String(forecast.date.suffix(5)))
                                .font(PerchTheme.Font.micro)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                        .frame(width: 60)
                        .padding(.vertical, PerchTheme.Spacing.small)
                        .background(PerchTheme.cardInnerBackground)
                        .cornerRadius(10)
                    }
                }
            }

            if !packingHints.isEmpty {
                Text("🎒 Pack: \(packingHints.joined(separator: ", "))")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
                    .padding(.top, 2)
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            Image(systemName: "airplane")
                .font(PerchTheme.Font.icon(PerchTheme.Icon.xxLarge))
                .foregroundColor(PerchTheme.textTertiary)

            Text("No upcoming trips")
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textSecondary)

            Text("Forward your booking confirmations to plans@tripit.com and they'll appear here automatically.")
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(PerchTheme.Spacing.xxLarge)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func segmentIcon(_ seg: ItineraryData) -> String {
        switch seg.segmentType {
        case "flight": return "airplane"
        case "hotel": return "bed.double"
        case "train": return "tram"
        case "car_rental": return "car"
        case "restaurant": return "fork.knife"
        default: return "mappin.circle"
        }
    }

    private func segmentStatusColor(_ seg: ItineraryData) -> Color {
        switch seg.status?.lowercased() {
        case "confirmed", "on_time": return PerchTheme.success
        case "delayed": return PerchTheme.warning
        case "cancelled": return PerchTheme.error
        case "pending": return PerchTheme.textTertiary
        default: return PerchTheme.accent
        }
    }

    private func statusEmoji(_ status: String) -> String {
        switch status {
        case "active": return "📍"
        case "upcoming": return "✈️"
        case "completed": return "✅"
        default: return "📌"
        }
    }

    private func statusBadge(trip: TripData) -> some View {
        HStack(spacing: 4) {
            Text(statusEmoji(trip.status))
            if trip.status == "active", let day = trip.currentTripDay, let total = trip.totalDays {
                Text("Day \(day)/\(total)")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.accent)
            } else if let days = trip.daysUntilStart, days > 0 {
                Text("in \(days)d")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)
            } else {
                Text(trip.status.capitalized)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(PerchTheme.cardInnerBackground)
        .cornerRadius(8)
    }

    private func formatTimezoneOffset(origin: String, destination: String) -> String {
        guard let originTz = TimeZone(identifier: origin),
              let destTz = TimeZone(identifier: destination) else { return "" }
        let diff = (destTz.secondsFromGMT() - originTz.secondsFromGMT()) / 3600
        if diff == 0 { return "Same timezone" }
        let sign = diff > 0 ? "+" : ""
        return "\(sign)\(diff)h from home"
    }

    private func uniquePackingHints(from forecasts: [(Record, WeatherForecastData)]) -> [String] {
        var seen: Set<String> = []

        return forecasts
            .flatMap { $0.1.packingHints ?? [] }
            .filter { hint in
                let normalized = hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalized.isEmpty, !seen.contains(normalized) else { return false }
                seen.insert(normalized)
                return true
            }
    }

    private func calendarEvents(for trip: TripData) -> [EventData] {
        guard let start = trip.startDateParsed,
              let end = trip.endDateParsed else { return [] }

        let calendar = Calendar.current
        let tripStart = calendar.startOfDay(for: start)
        let tripEnd = calendar.startOfDay(for: end)

        return dashboardViewModel.calendarRecords.compactMap { record -> EventData? in
            guard record.type == .event,
                  let event = record.asEvent() else { return nil }

            let eventDay = calendar.startOfDay(for: event.start)
            guard eventDay >= tripStart, eventDay <= tripEnd else { return nil }
            return event
        }
        .sorted { $0.start < $1.start }
    }

    private func calendarSection(events: [EventData], trip: TripData) -> some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
            Text("CALENDAR")
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textSecondary)
                .tracking(1)

            VStack(spacing: PerchTheme.Spacing.small) {
                ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                    Button(action: { openInCalendar(event) }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(calendarEventTimeText(for: event, trip: trip)) — \(event.title)")
                                .font(PerchTheme.Font.body)
                                .foregroundColor(PerchTheme.textPrimary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if let location = event.location, !location.isEmpty {
                                Text(location)
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(PerchTheme.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(PerchTheme.Spacing.medium)
                        .background(PerchTheme.cardInnerBackground)
                        .cornerRadius(10)
                    }
                    .buttonStyle(CardPressStyle())

                    if index < events.count - 1 {
                        Rectangle()
                            .fill(PerchTheme.border)
                            .frame(height: 0.5)
                    }
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }

    private func calendarEventTimeText(for event: EventData, trip: TripData) -> String {
        guard let originId = trip.originTz,
              let destinationId = trip.destinationTz,
              originId != destinationId,
              let originTz = TimeZone(identifier: originId),
              let destinationTz = TimeZone(identifier: destinationId) else {
            return "📅 \(PerchFormatters.time24h.string(from: event.start))"
        }

        let destinationTime = formattedTime(event.start, in: destinationTz, includeAbbreviation: true)
        let originTime = formattedTime(event.start, in: originTz, includeAbbreviation: false)
        return "📅 \(destinationTime) (\(originTime) your time)"
    }

    private func formattedTime(_ date: Date, in timeZone: TimeZone, includeAbbreviation: Bool) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = Locale.current
        formatter.dateFormat = includeAbbreviation ? "HH:mm z" : "HH:mm"
        return formatter.string(from: date)
    }

    private func openInCalendar(_ event: EventData) {
        let interval = event.start.timeIntervalSinceReferenceDate
        if let url = URL(string: "calshow:\(interval)") {
            UIApplication.shared.open(url)
        }
    }
}
