import Foundation
import Observation

// MARK: - TravelViewModel

/// Manages the state of the Travel section.
/// Records are fed from DashboardViewModel (single-fetch architecture).
@Observable
@MainActor
final class TravelViewModel {
    // MARK: - Properties

    var records: [Record] = []

    // MARK: - Trip Records

    /// All trip records, sorted by start date (upcoming first).
    var trips: [(Record, TripData)] {
        records.compactMap { record -> (Record, TripData)? in
            guard let trip = record.asTrip() else { return nil }
            return (record, trip)
        }.sorted { ($0.1.startDateParsed ?? .distantFuture) < ($1.1.startDateParsed ?? .distantFuture) }
    }

    /// The currently active trip, if any.
    var activeTrip: (Record, TripData)? {
        trips.first { $0.1.status == "active" }
    }

    /// The next upcoming trip (not yet active).
    var upcomingTrip: (Record, TripData)? {
        trips.first { $0.1.status == "upcoming" }
    }

    /// The most relevant trip: active takes priority, then upcoming.
    var currentTrip: (Record, TripData)? {
        activeTrip ?? upcomingTrip
    }

    /// Past trips, most recent first.
    var pastTrips: [(Record, TripData)] {
        trips.filter { $0.1.status == "completed" }
            .sorted { ($0.1.startDateParsed ?? .distantPast) > ($1.1.startDateParsed ?? .distantPast) }
    }

    // MARK: - Itinerary

    /// All itinerary segments for a given trip, sorted chronologically.
    func segments(for tripId: String) -> [(Record, ItineraryData)] {
        records.compactMap { record -> (Record, ItineraryData)? in
            guard let seg = record.asItinerary(), seg.tripId == tripId else { return nil }
            return (record, seg)
        }.sorted {
            let date0 = $0.1.departure ?? $0.1.checkIn ?? .distantFuture
            let date1 = $1.1.departure ?? $1.1.checkIn ?? .distantFuture
            return date0 < date1
        }
    }

    /// Flight segments for a trip.
    func flights(for tripId: String) -> [(Record, ItineraryData)] {
        segments(for: tripId).filter { $0.1.isFlight }
    }

    /// Hotel segments for a trip.
    func hotels(for tripId: String) -> [(Record, ItineraryData)] {
        segments(for: tripId).filter { $0.1.isHotel }
    }

    /// The next upcoming segment (departure/check-in in the future).
    func nextSegment(for tripId: String) -> (Record, ItineraryData)? {
        segments(for: tripId).first { seg in
            let date = seg.1.departure ?? seg.1.checkIn ?? .distantPast
            return date > .now
        }
    }

    // MARK: - Alerts

    /// Active alerts for a given trip, most recent first.
    func alerts(for tripId: String) -> [(Record, TravelAlertData)] {
        records.compactMap { record -> (Record, TravelAlertData)? in
            guard let alert = record.asTravelAlert(), alert.tripId == tripId else { return nil }
            return (record, alert)
        }.sorted { $0.0.createdAt > $1.0.createdAt }
    }

    /// Whether there are any critical/warning alerts for the current trip.
    var hasActiveAlerts: Bool {
        guard let trip = currentTrip else { return false }
        return alerts(for: trip.1.tripId).contains { $0.1.isCritical || $0.1.isWarning }
    }

    // MARK: - Weather

    /// Weather forecasts for a trip, sorted by date.
    func weatherForecasts(for tripId: String) -> [(Record, WeatherForecastData)] {
        records.compactMap { record -> (Record, WeatherForecastData)? in
            guard let weather = record.asWeatherForecast(), weather.tripId == tripId else { return nil }
            return (record, weather)
        }.sorted { $0.1.date < $1.1.date }
    }

    /// Summary weather for the trip (average temp, dominant condition).
    func weatherSummary(for tripId: String) -> (avgTemp: Double, condition: String, emoji: String)? {
        let forecasts = weatherForecasts(for: tripId)
        guard !forecasts.isEmpty else { return nil }
        let temps = forecasts.compactMap { $0.1.tempAvg }
        guard !temps.isEmpty else { return nil }
        let avg = temps.reduce(0, +) / Double(temps.count)
        // Most common condition
        let conditions = forecasts.compactMap { $0.1.condition }
        let conditionCounts = Dictionary(grouping: conditions, by: { $0 }).mapValues { $0.count }
        let dominant = conditionCounts.max(by: { $0.value < $1.value })?.key ?? "clear"
        let emoji = forecasts.first { $0.1.condition == dominant }?.1.conditionEmoji ?? "🌤"
        return (avgTemp: avg, condition: dominant, emoji: emoji)
    }

    // MARK: - Travel Tasks

    /// Pre-trip tasks (no date set) for a given trip, unchecked first.
    func preTripTasks(for tripId: String) -> [(Record, TravelTaskData)] {
        records.compactMap { record -> (Record, TravelTaskData)? in
            guard let task = record.asTravelTask(), task.tripId == tripId, task.isPretripTask else { return nil }
            return (record, task)
        }.sorted { ($0.1.done ? 1 : 0) < ($1.1.done ? 1 : 0) }
    }

    /// Day-linked tasks for a specific date string (yyyy-MM-dd).
    func dayTasks(for tripId: String, on date: String) -> [(Record, TravelTaskData)] {
        records.compactMap { record -> (Record, TravelTaskData)? in
            guard let task = record.asTravelTask(), task.tripId == tripId, task.date == date else { return nil }
            return (record, task)
        }.sorted { ($0.1.done ? 1 : 0) < ($1.1.done ? 1 : 0) }
    }

    /// All tasks for a trip with completion stats.
    func taskStats(for tripId: String) -> (total: Int, done: Int) {
        let all = records.compactMap { $0.asTravelTask() }.filter { $0.tripId == tripId }
        return (total: all.count, done: all.filter(\.done).count)
    }

    // MARK: - Home Card Data

    /// Whether to show the travel card on the Home screen.
    var shouldShowHomeCard: Bool {
        guard let trip = currentTrip else { return false }
        // Show if trip is active, or upcoming within 7 days
        if trip.1.status == "active" { return true }
        if let days = trip.1.daysUntilStart, days <= 7 { return true }
        return false
    }

    /// The urgency tier for the home card visual treatment.
    enum CardTier {
        case upcoming       // >24h out, muted
        case travelDay      // <24h or active, elevated
        case disruption     // alert active, warning
    }

    var homeCardTier: CardTier {
        guard let trip = currentTrip else { return .upcoming }
        if hasActiveAlerts { return .disruption }
        if trip.1.status == "active" { return .travelDay }
        if let days = trip.1.daysUntilStart, days <= 1 { return .travelDay }
        return .upcoming
    }
}
