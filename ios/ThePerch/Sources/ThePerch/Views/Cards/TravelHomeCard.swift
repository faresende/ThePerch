import SwiftUI

/// Contextual travel banner for the Home screen.
/// Appears above regular cards when a trip is upcoming (≤7 days) or active.
/// Three visual tiers: upcoming (muted), travel day (elevated), disruption (warning).
struct TravelHomeCard: View {
    let records: [Record]
    let deliveries: [DeliveryData]

    @Environment(TravelViewModel.self) private var travelVM
    @Environment(\.perchPalette) private var palette

    var body: some View {
        if let (_, trip) = travelVM.currentTrip, travelVM.shouldShowHomeCard {
            let tripId = trip.tripId
            let tier = travelVM.homeCardTier
            let segments = travelVM.segments(for: tripId)
            let alerts = travelVM.alerts(for: tripId)
            let weather = travelVM.weatherSummary(for: tripId)
            let nextSeg = travelVM.nextSegment(for: tripId)

            TodayCard {
                VStack(alignment: .leading, spacing: 0) {
                    TodayEyebrow(
                        label: "TRAVEL · \(trip.destination.uppercased())",
                        accent: palette.kinetic,
                        freshness: travelFreshness(trip: trip)
                    )
                    TodayPhrase(text: travelPhrase(for: trip))

                    // Header (dates + weather + day counter)
                    headerView(trip: trip, weather: weather, tier: tier)
                        .padding(.bottom, alerts.isEmpty && nextSeg == nil ? 0 : 12)

                    // Active alerts
                    if !alerts.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(alerts.prefix(2), id: \.0.id) { _, alert in
                                alertRow(alert: alert)
                            }
                        }
                        .padding(.bottom, 10)
                    }

                    // Next segment
                    if let (_, seg) = nextSeg {
                        nextSegmentView(segment: seg)
                    }

                    // Cross-domain: deliveries arriving while away
                    let awayDeliveries = crossDomainDeliveries(tripStart: trip.startDateParsed, tripEnd: trip.endDateParsed)
                    if !awayDeliveries.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 11))
                            Text("\(awayDeliveries.count) deliver\(awayDeliveries.count == 1 ? "y" : "ies") arriving while away")
                                .font(PerchTheme.Font.caption)
                        }
                        .foregroundColor(palette.muted)
                        .padding(.top, 10)
                    }

                    // Segment summary (compact)
                    if segments.count > 1 {
                        segmentSummaryView(segments: segments, trip: trip)
                            .padding(.top, 10)
                    }
                }
            }
            // Round 10 audit (F5): dropped the `records → travelVM.records`
            // writes here. After R9 hoisted TravelViewModel to .environment,
            // HubTab is the canonical writer (subscribes to the trimmed
            // `travelRecords` slice on the right cadence). This card was
            // re-firing recomputeTrips on EVERY allRecords change.
        }
    }

    private func travelFreshness(trip: TripData) -> String {
        if trip.effectiveStatus == "active" {
            if let day = trip.currentTripDay, let total = trip.totalDays {
                return "Day \(day) of \(total)"
            }
            return "Active"
        }
        if let days = trip.daysUntilStart, days > 0 {
            return "\(days) day\(days == 1 ? "" : "s")"
        }
        return "Today"
    }

    private func travelPhrase(for trip: TripData) -> String {
        let phase: PerchPhrase.TravelPhase = {
            switch trip.effectiveStatus {
            case "active": return .active
            default:
                if (trip.daysUntilStart ?? 99) <= 0 { return .today }
                return .upcoming
            }
        }()
        return PerchPhrase.travelPhrase(phase: phase)
    }

    // MARK: - Header

    @ViewBuilder
    private func headerView(trip: TripData, weather: (avgTemp: Double, condition: String, emoji: String)?, tier: TravelViewModel.CardTier) -> some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            Image(systemName: tier == .disruption ? "exclamationmark.triangle.fill" : "suitcase.fill")
                .font(PerchTheme.Font.caption)
                .foregroundColor(tierAccentColor(tier))

            VStack(alignment: .leading, spacing: 2) {
                Text(trip.destination.uppercased())
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)
                    .tracking(1)

                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    if trip.effectiveStatus == "active", let day = trip.currentTripDay, let total = trip.totalDays {
                        Text("Day \(day) of \(total)")
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(PerchTheme.textPrimary)
                    } else if let days = trip.daysUntilStart {
                        Text(days == 0 ? "Today" : days == 1 ? "Tomorrow" : "in \(days) days")
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(PerchTheme.textPrimary)
                    }

                    if let weather {
                        Text("·")
                            .foregroundColor(PerchTheme.textTertiary)
                        Text("\(weather.emoji) \(Int(weather.avgTemp))°C")
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                }
            }

            Spacer()

            if trip.effectiveStatus == "active" {
                Text("📍")
                    .font(PerchTheme.Font.body)
            }
        }
    }

    // MARK: - Alert Row

    @ViewBuilder
    private func alertRow(alert: TravelAlertData) -> some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            Circle()
                .fill(alert.isCritical ? PerchTheme.error : PerchTheme.warning)
                .frame(width: 6, height: 6)

            Text(alert.message)
                .font(PerchTheme.Font.caption)
                .foregroundColor(alert.isCritical ? PerchTheme.error : PerchTheme.warning)
                .lineLimit(1)
        }
    }

    // MARK: - Next Segment

    @ViewBuilder
    private func nextSegmentView(segment: ItineraryData) -> some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            Image(systemName: segmentIcon(segment))
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.accent)
                .frame(width: 20)

            if segment.isFlight {
                flightRow(segment)
            } else if segment.isHotel {
                hotelRow(segment)
            } else {
                genericSegmentRow(segment)
            }
        }
        .padding(PerchTheme.Spacing.small)
        .background(PerchTheme.cardInnerBackground)
        .cornerRadius(8)
    }

    @ViewBuilder
    private func flightRow(_ seg: ItineraryData) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(seg.flightLabel ?? "Flight")
                    .font(PerchTheme.Font.body)
                    .fontWeight(.semibold)
                    .foregroundColor(PerchTheme.textPrimary)

                if let origin = seg.origin, let dest = seg.destination {
                    Text("\(origin)→\(dest)")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textSecondary)
                }

                Spacer()

                if let gate = seg.gate {
                    Text("Gate \(gate)")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.accent)
                }
            }

            HStack {
                if let dep = seg.departure {
                    if let remaining = seg.timeUntilDeparture {
                        let hours = Int(remaining / 3600)
                        let mins = Int(remaining.truncatingRemainder(dividingBy: 3600) / 60)
                        if hours > 0 {
                            Text("Boards \(PerchFormatters.time24h.string(from: dep)) · \(hours)h \(mins)m")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textSecondary)
                        } else {
                            Text("Boards \(PerchFormatters.time24h.string(from: dep)) · \(mins)m")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.accent)
                        }
                    } else {
                        Text(PerchFormatters.eventDateTime.string(from: dep))
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                }

                Spacer()

                if let seat = seg.seat {
                    Text("Seat \(seat)")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func hotelRow(_ seg: ItineraryData) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(seg.name ?? "Hotel")
                .font(PerchTheme.Font.body)
                .fontWeight(.semibold)
                .foregroundColor(PerchTheme.textPrimary)

            HStack {
                if let checkIn = seg.checkIn {
                    Text("Check-in \(PerchFormatters.time24h.string(from: checkIn))")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textSecondary)
                }

                Spacer()

                if let conf = seg.confirmation {
                    Text(conf)
                        .font(PerchTheme.Font.captionNumeric)
                        .foregroundColor(PerchTheme.textTertiary)
                        .onTapGesture {
                            UIPasteboard.general.string = conf
                            PerchHaptics.light()
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func genericSegmentRow(_ seg: ItineraryData) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(seg.name ?? seg.segmentType.capitalized)
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textPrimary)

            if let dep = seg.departure {
                Text(PerchFormatters.eventDateTime.string(from: dep))
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)
            }
        }
    }

    // MARK: - Segment Summary

    @ViewBuilder
    private func segmentSummaryView(segments: [(Record, ItineraryData)], trip: TripData) -> some View {
        let flights = segments.filter { $0.1.isFlight }.count
        let hotels = segments.filter { $0.1.isHotel }.count
        let other = segments.count - flights - hotels

        HStack(spacing: PerchTheme.Spacing.medium) {
            if flights > 0 {
                Text("\(flights) flight\(flights == 1 ? "" : "s")")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
            }
            if hotels > 0 {
                Text("\(hotels) hotel\(hotels == 1 ? "" : "s")")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
            }
            if other > 0 {
                Text("\(other) item\(other == 1 ? "" : "s")")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
            }

            Spacer()

            if let start = trip.startDateParsed, let end = trip.endDateParsed {
                Text("\(PerchFormatters.shortDate.string(from: start)) – \(PerchFormatters.shortDate.string(from: end))")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
            }
        }
    }

    // MARK: - Styling

    /// Finds canonical deliveries with ETAs during the trip window.
    private func crossDomainDeliveries(tripStart: Date?, tripEnd: Date?) -> [DeliveryData] {
        guard let start = tripStart, let end = tripEnd else { return [] }
        return deliveries.filter { delivery in
            let status = delivery.status.lowercased().replacingOccurrences(of: " ", with: "_")
            guard status != "delivered" && status != "cancelled" else { return false }
            if let eta = delivery.eta, eta >= start && eta <= end {
                return true
            }
            return false
        }
    }

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

    private func tierAccentColor(_ tier: TravelViewModel.CardTier) -> Color {
        switch tier {
        case .upcoming: return PerchTheme.accent
        case .travelDay: return PerchTheme.accent
        case .disruption: return PerchTheme.error
        }
    }

    @ViewBuilder
    private func cardBackground(tier: TravelViewModel.CardTier) -> some View {
        switch tier {
        case .upcoming:
            PerchTheme.cardBackground
        case .travelDay:
            PerchTheme.cardHover
        case .disruption:
            PerchTheme.error.opacity(0.08)
        }
    }

    @ViewBuilder
    private func cardBorder(tier: TravelViewModel.CardTier) -> some View {
        switch tier {
        case .upcoming:
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                .stroke(PerchTheme.border, lineWidth: PerchTheme.Card.borderWidth)
        case .travelDay:
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                .stroke(PerchTheme.accent.opacity(0.4), lineWidth: 1.5)
        case .disruption:
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                .stroke(PerchTheme.error.opacity(0.5), lineWidth: 1.5)
        }
    }
}
