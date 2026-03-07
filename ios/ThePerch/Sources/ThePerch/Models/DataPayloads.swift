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
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.date(from: date)
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
    }

    /// The best available title (enriched if available, otherwise original).
    var displayTitle: String {
        enrichedTitle ?? originalTitle ?? domain ?? url
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
}
