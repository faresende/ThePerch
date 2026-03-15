import Foundation

// MARK: - Measurement Data

/// Structured data for a measurement record.
struct MeasurementData: Codable {
    let metric: String
    let value: Double
    let unit: String
    let context: String?
    let timestamp: Date?
    let target: Double?         // Optional daily target (for calories, macros, etc.)
    let displayValue: String?   // Optional formatted display value (e.g. "120/80")

    enum CodingKeys: String, CodingKey {
        case metric
        case value
        case unit
        case context
        case timestamp
        case target
        case displayValue = "display_value"
    }
}

// MARK: - Macros Data

/// Structured data for a daily macronutrient record with targets.
struct MacrosData: Codable {
    let protein: Double
    let proteinTarget: Double?
    let carbs: Double
    let carbsTarget: Double?
    let fat: Double
    let fatTarget: Double?
    let date: String?

    enum CodingKeys: String, CodingKey {
        case protein
        case proteinTarget = "protein_target"
        case carbs
        case carbsTarget = "carbs_target"
        case fat
        case fatTarget = "fat_target"
        case date
    }

    var totalGrams: Double { protein + carbs + fat }

    /// Parses the date string (e.g. "2026-03-06") into a Date object.
    var dateAsDate: Date? {
        guard let date else { return nil }
        return PerchFormatters.isoDate.date(from: date)
    }
}

// MARK: - Cron Job Data

/// Structured data for a scheduled cron job (for admin dashboard).
struct CronJobData: Codable {
    let name: String
    let schedule: String
    let model: String?
    let nextRunAt: Date?
    let lastRunAt: Date?
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case name, schedule, model, enabled
        case nextRunAt = "next_run_at"
        case lastRunAt = "last_run_at"
    }
}

// MARK: - Gateway Status Data

/// Structured data for the OpenClaw gateway status.
struct GatewayStatusData: Codable {
    let isRunning: Bool
    let activeModels: [ActiveModel]?
    let activeSessionCount: Int?
    let activeHourly: [Int]?
    let peakHour: Int?

    enum CodingKeys: String, CodingKey {
        case isRunning = "is_running"
        case activeModels = "active_models"
        case activeSessionCount = "active_session_count"
        case activeHourly = "active_hourly"
        case peakHour = "peak_hour"
    }
}

struct ActiveModel: Codable {
    let modelId: String
    let jobCount: Int

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case jobCount = "job_count"
    }
}

// MARK: - Delivery Data

/// Structured data for a delivery record.
struct DeliveryData: Codable {
    let orderId: String
    let carrier: String
    let trackingNumber: String
    let status: String
    let eta: Date?
    let items: [DeliveryItem]
    let trackingUrl: String?

    enum CodingKeys: String, CodingKey {
        case orderId = "order_id"
        case carrier
        case trackingNumber = "tracking_number"
        case status
        case eta
        case items
        case trackingUrl = "tracking_url"
    }
}

/// A single item in a delivery.
struct DeliveryItem: Codable {
    let name: String
    let quantity: Int
    let description: String?
}

// MARK: - Event Data

/// Structured data for an event record.
struct EventData: Codable {
    let title: String
    let start: Date
    let end: Date
    let location: String?
    let agentNotes: String?

    enum CodingKeys: String, CodingKey {
        case title
        case start
        case end
        case location
        case agentNotes = "agent_notes"
    }
}

// MARK: - Status Data

/// Structured data for a status record.
struct StatusData: Codable {
    let state: String
    let uptimeHours: Double?
    let lastActivity: Date?
    let currentTask: String?

    enum CodingKeys: String, CodingKey {
        case state
        case uptimeHours = "uptime_hours"
        case lastActivity = "last_activity"
        case currentTask = "current_task"
    }
}

// MARK: - Reminder Data

/// Structured data for a reminder record.
struct ReminderData: Codable {
    let title: String
    let due: Date
    let list: String?
    let completed: Bool
    let source: String?
}

// MARK: - Cost Summary Data

/// Structured data for a cost summary record.
struct CostSummaryData: Codable {
    let period: String
    let date: Date
    let totalCostUsd: Double
    let breakdown: [String: Double]

    enum CodingKeys: String, CodingKey {
        case period
        case date
        case totalCostUsd = "total_cost_usd"
        case breakdown
    }
}

// MARK: - Text Note Data

/// Structured data for a text note record.
struct TextNoteData: Codable {
    let body: String
    let tags: [String]?
}

// MARK: - Checklist Data

/// Structured data for a checklist record.
struct ChecklistData: Codable {
    let items: [ChecklistItem]
}

/// A single item in a checklist.
struct ChecklistItem: Codable {
    let text: String
    var done: Bool
}

// MARK: - Bookmark Data

/// Processing status for bookmarks submitted via Share Extension.
enum BookmarkStatus: String, Codable {
    case pending     // Just submitted, waiting for OpenClaw to process
    case processing  // Archie is fetching/analyzing the page
    case processed   // Fully enriched with summary, tags, metadata
    case failed      // Processing failed (page unreachable, etc.)
}

/// Source system for a bookmark (Karakeep for read-later, Paperless for documents).
enum BookmarkSource: String, Codable {
    case karakeep    // Read-later / articles
    case paperless   // Documents / receipts
}

/// Structured data for a bookmark record.
/// Bookmarks are submitted from the iOS Share Extension or Safari Extension,
/// then asynchronously enriched by the Archie agent on OpenClaw.
struct BookmarkData: Codable {
    let url: String
    let originalTitle: String?
    let enrichedTitle: String?
    let summary: String?
    let tags: [String]
    let status: BookmarkStatus
    let domain: String?
    let imageUrl: String?
    let readingTimeMinutes: Int?
    let submittedFrom: String?  // "ios_share", "safari_extension", "telegram"
    let processedAt: Date?
    let source: BookmarkSource?
    let fileType: String?
    let fileName: String?

    enum CodingKeys: String, CodingKey {
        case url
        case originalTitle = "original_title"
        case enrichedTitle = "enriched_title"
        case summary
        case tags
        case status
        case domain
        case imageUrl = "image_url"
        case readingTimeMinutes = "reading_time_minutes"
        case submittedFrom = "submitted_from"
        case processedAt = "processed_at"
        case source
        case fileType = "file_type"
        case fileName = "file_name"
    }

    /// The best available title (enriched if available, otherwise original).
    var displayTitle: String {
        enrichedTitle ?? originalTitle ?? domain ?? url
    }
}

// MARK: - Medication Checklist Data

/// Structured data for a daily medication checklist record.
struct MedicationChecklistData: Codable {
    let items: [MedicationItem]

    struct MedicationItem: Codable, Identifiable {
        let id: String
        let name: String
        var isChecked: Bool
        let schedule: String?

        enum CodingKeys: String, CodingKey {
            case id, name, schedule
            case isChecked = "is_checked"
        }
    }
}

// MARK: - Weather Data

/// Structured data for a weather forecast record.
struct WeatherData: Codable {
    let temperature: Double
    let feelsLike: Double?
    let conditions: String
    let icon: String
    let rainProbability: Double?
    let high: Double?
    let low: Double?

    enum CodingKeys: String, CodingKey {
        case temperature, conditions, icon, high, low
        case feelsLike = "feels_like"
        case rainProbability = "rain_probability"
    }
}

// MARK: - Email Summary Data

/// Structured data for an important emails summary record.
struct EmailSummaryData: Codable {
    let emails: [EmailItem]
    let totalUnread: Int?

    enum CodingKeys: String, CodingKey {
        case emails
        case totalUnread = "total_unread"
    }

    struct EmailItem: Codable, Identifiable {
        let id: String
        let sender: String
        let subject: String
        let receivedAt: String
        let isFlagged: Bool
        let isUrgent: Bool

        enum CodingKeys: String, CodingKey {
            case id, sender, subject
            case receivedAt = "received_at"
            case isFlagged = "is_flagged"
            case isUrgent = "is_urgent"
        }
    }
}

// MARK: - Admin Command Data

/// Structured data for a remote admin command (restart gateway, doctor fix, etc.).
struct AdminCommandData: Codable {
    let command: AdminCommand
    let status: CommandStatus
    let result: CommandResult?
    let createdAt: String
    let executedAt: String?

    enum AdminCommand: String, Codable {
        case restartGateway = "restart_gateway"
        case doctorFix = "doctor_fix"
        case statusCheck = "status_check"

        var displayName: String {
            switch self {
            case .restartGateway: return "Restart Gateway"
            case .doctorFix: return "Doctor Fix"
            case .statusCheck: return "Status Check"
            }
        }

        var icon: String {
            switch self {
            case .restartGateway: return "arrow.clockwise.circle.fill"
            case .doctorFix: return "stethoscope.circle.fill"
            case .statusCheck: return "checkmark.circle.fill"
            }
        }
    }

    enum CommandStatus: String, Codable {
        case pending, executing, completed, failed

        var displayName: String {
            switch self {
            case .pending: return "Pending"
            case .executing: return "Executing"
            case .completed: return "Completed"
            case .failed: return "Failed"
            }
        }
    }

    struct CommandResult: Codable {
        let success: Bool
        let message: String?
        let details: String?
    }

    enum CodingKeys: String, CodingKey {
        case command, status, result
        case createdAt = "created_at"
        case executedAt = "executed_at"
    }
}

// MARK: - Trip Data

/// Structured data for a trip record (the container for a journey).
struct TripData: Codable {
    let destination: String
    let destinationCountry: String?
    let origin: String?
    let originTz: String?
    let destinationTz: String?
    let startDate: String        // yyyy-MM-dd
    let endDate: String          // yyyy-MM-dd
    let status: String           // upcoming, active, completed
    let tripId: String

    enum CodingKeys: String, CodingKey {
        case destination
        case destinationCountry = "destination_country"
        case origin
        case originTz = "origin_tz"
        case destinationTz = "destination_tz"
        case startDate = "start_date"
        case endDate = "end_date"
        case status
        case tripId = "trip_id"
    }

    /// Parsed start date.
    var startDateParsed: Date? {
        PerchFormatters.isoDate.date(from: startDate)
    }

    /// Parsed end date.
    var endDateParsed: Date? {
        PerchFormatters.isoDate.date(from: endDate)
    }

    /// Days until trip starts (negative if already started).
    var daysUntilStart: Int? {
        guard let start = startDateParsed else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: start).day
    }

    /// Current day number within the trip (1-indexed). Nil if not active.
    var currentTripDay: Int? {
        guard status == "active",
              let start = startDateParsed else { return nil }
        let days = Calendar.current.dateComponents([.day], from: start, to: .now).day ?? 0
        return days + 1
    }

    /// Total trip duration in days.
    var totalDays: Int? {
        guard let start = startDateParsed, let end = endDateParsed else { return nil }
        return Calendar.current.dateComponents([.day], from: start, to: end).day
    }
}

// MARK: - Itinerary Data

/// Structured data for a travel itinerary segment (flight, hotel, train, etc.).
struct ItineraryData: Codable {
    let tripId: String
    let segmentType: String      // flight, hotel, train, car_rental, restaurant
    let carrier: String?
    let flightNumber: String?
    let origin: String?          // IATA code for flights, city/address otherwise
    let destination: String?
    let departure: Date?
    let arrival: Date?
    let status: String?          // confirmed, on_time, delayed, cancelled, gate_change
    let confirmation: String?
    let gate: String?
    let seat: String?
    let name: String?            // Hotel name, restaurant name, etc.
    let checkIn: Date?
    let checkOut: Date?
    let address: String?

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case segmentType = "segment_type"
        case carrier
        case flightNumber = "flight_number"
        case origin, destination
        case departure, arrival
        case status, confirmation, gate, seat
        case name
        case checkIn = "check_in"
        case checkOut = "check_out"
        case address
    }

    /// Whether this is a flight segment.
    var isFlight: Bool { segmentType == "flight" }

    /// Whether this is a hotel segment.
    var isHotel: Bool { segmentType == "hotel" }

    /// Formatted flight label (e.g. "TP668").
    var flightLabel: String? {
        guard let number = flightNumber else { return nil }
        if let carrier { return "\(carrier) \(number)" }
        return number
    }

    /// Time until departure (nil if in the past or no departure date).
    var timeUntilDeparture: TimeInterval? {
        guard let dep = departure, dep > .now else { return nil }
        return dep.timeIntervalSince(.now)
    }
}

// MARK: - Travel Alert Data

/// Structured data for a travel disruption alert.
struct TravelAlertData: Codable {
    let tripId: String
    let alertType: String        // gate_change, delay, cancellation, disruption
    let severity: String         // info, warning, critical
    let message: String
    let source: String?          // tripit_email, airline_email, manual
    let flightNumber: String?

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case alertType = "alert_type"
        case severity
        case message
        case source
        case flightNumber = "flight_number"
    }

    var isCritical: Bool { severity == "critical" }
    var isWarning: Bool { severity == "warning" }
}

// MARK: - Weather Forecast Data

/// Structured data for a destination weather forecast.
struct WeatherForecastData: Codable {
    let tripId: String
    let destination: String
    let date: String             // yyyy-MM-dd
    let tempHigh: Double?
    let tempLow: Double?
    let tempAvg: Double?
    let condition: String?       // sunny, cloudy, rain, snow, etc.
    let summary: String?         // Human-readable summary
    let packingHints: [String]?

    enum CodingKeys: String, CodingKey {
        case tripId = "trip_id"
        case destination, date
        case tempHigh = "temp_high"
        case tempLow = "temp_low"
        case tempAvg = "temp_avg"
        case condition, summary
        case packingHints = "packing_hints"
    }

    /// Weather emoji based on condition.
    var conditionEmoji: String {
        switch condition?.lowercased() {
        case "sunny", "clear": return "☀️"
        case "partly_cloudy", "partly cloudy": return "⛅"
        case "cloudy", "overcast": return "☁️"
        case "rain", "rainy", "showers": return "🌧"
        case "thunderstorm": return "⛈"
        case "snow", "snowy": return "🌨"
        case "windy": return "💨"
        case "fog", "foggy": return "🌫"
        default: return "🌤"
        }
    }
}

// MARK: - Data Payload Decoding Extension

/// Extension to Record for convenient typed data decoding.
extension Record {
    /// Decodes the measurement data from this record.
    func asMeasurement() -> MeasurementData? {
        decodeData(as: MeasurementData.self)
    }

    /// Decodes the delivery data from this record.
    func asDelivery() -> DeliveryData? {
        decodeData(as: DeliveryData.self)
    }

    /// Decodes the event data from this record.
    func asEvent() -> EventData? {
        decodeData(as: EventData.self)
    }

    /// Decodes the status data from this record.
    func asStatus() -> StatusData? {
        decodeData(as: StatusData.self)
    }

    /// Decodes the reminder data from this record.
    func asReminder() -> ReminderData? {
        decodeData(as: ReminderData.self)
    }

    /// Decodes the cost summary data from this record.
    func asCostSummary() -> CostSummaryData? {
        decodeData(as: CostSummaryData.self)
    }

    /// Decodes the text note data from this record.
    func asTextNote() -> TextNoteData? {
        decodeData(as: TextNoteData.self)
    }

    /// Decodes the checklist data from this record.
    func asChecklist() -> ChecklistData? {
        decodeData(as: ChecklistData.self)
    }

    /// Decodes the bookmark data from this record.
    func asBookmark() -> BookmarkData? {
        decodeData(as: BookmarkData.self)
    }

    /// Decodes the macros data from this record.
    func asMacros() -> MacrosData? {
        decodeData(as: MacrosData.self)
    }

    /// Decodes cron job data from this record.
    func asCronJob() -> CronJobData? {
        decodeData(as: CronJobData.self)
    }

    /// Decodes gateway status data from this record.
    func asGatewayStatus() -> GatewayStatusData? {
        decodeData(as: GatewayStatusData.self)
    }

    /// Decodes medication checklist data from this record.
    func asMedications() -> MedicationChecklistData? {
        decodeData(as: MedicationChecklistData.self)
    }

    /// Decodes weather data from this record.
    func asWeather() -> WeatherData? {
        decodeData(as: WeatherData.self)
    }

    /// Decodes email summary data from this record.
    func asEmailSummary() -> EmailSummaryData? {
        decodeData(as: EmailSummaryData.self)
    }

    /// Decodes admin command data from this record.
    func asAdminCommand() -> AdminCommandData? {
        decodeData(as: AdminCommandData.self)
    }

    // MARK: - Travel

    /// Decodes trip data from this record.
    func asTrip() -> TripData? {
        decodeData(as: TripData.self)
    }

    /// Decodes itinerary segment data from this record.
    func asItinerary() -> ItineraryData? {
        decodeData(as: ItineraryData.self)
    }

    /// Decodes travel alert data from this record.
    func asTravelAlert() -> TravelAlertData? {
        decodeData(as: TravelAlertData.self)
    }

    /// Decodes weather forecast data from this record.
    func asWeatherForecast() -> WeatherForecastData? {
        decodeData(as: WeatherForecastData.self)
    }
}
