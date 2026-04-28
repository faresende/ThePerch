import Foundation

struct MealRecord: Sendable {
    let id: UUID
    let mealName: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let analysis: String
    let photoURL: String?
    let corrected: Bool
    let mealTime: Date
    let confidence: Double

    init(from record: Record) {
        let data = record.data.objectValue ?? [:]

        self.id = record.id
        self.mealName = data["meal_name"]?.stringValue ?? record.title
        self.calories = data["calories"]?.numberValue ?? 0
        self.protein = data["protein"]?.numberValue ?? 0
        self.carbs = data["carbs"]?.numberValue ?? 0
        self.fat = data["fat"]?.numberValue ?? 0
        self.fiber = data["fiber"]?.numberValue ?? 0
        self.analysis = data["analysis"]?.stringValue ?? ""
        self.photoURL = data["photo_url"]?.stringValue
        self.corrected = data["corrected"]?.boolValue ?? false
        self.mealTime = Self.parseDate(from: data["meal_time"]) ?? record.createdAt
        self.confidence = data["confidence"]?.numberValue ?? 0
    }

    private static func parseDate(from value: JSONValue?) -> Date? {
        guard let value else { return nil }

        if let timestamp = value.numberValue {
            return Date(timeIntervalSince1970: timestamp)
        }

        guard let string = value.stringValue else { return nil }

        if let date = Self.isoWithFractional.date(from: string) {
            return date
        }
        if let date = Self.isoBasic.date(from: string) {
            return date
        }
        return PerchFormatters.iso8601.date(from: string)
    }

    // Phase 3 perf: cached formatters. Per-render decoding on every
    // nutrition record fetch was creating two ISO8601DateFormatter
    // instances per row. Now once at type init.
    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()
}

struct MealSuggestion: Codable, Identifiable, Sendable {
    let mealName: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let analysisLine: String

    var id: String {
        "\(mealName)-\(Int(calories))-\(analysisLine)"
    }

    enum CodingKeys: String, CodingKey {
        case mealName = "meal_name"
        case calories
        case protein
        case carbs
        case fat
        case analysisLine = "analysis_line"
    }
}

struct NutritionTargets: Sendable, Equatable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    init(
        calories: Double = 2200,
        protein: Double = 180,
        carbs: Double = 250,
        fat: Double = 70
    ) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    static func resolved(
        for date: Date,
        records: [Record],
        calendar: Calendar = .current
    ) -> NutritionTargets {
        let dateString = PerchFormatters.isoDate.string(from: date)
        var targets = NutritionTargets()

        // Primary source: BioChecha's progress_summary record for today. Has
        // `target_calories` computed from the day type (training/pilates/rest)
        // plus the matched calendar event, so it's the authoritative target.
        //
        // RecordType doesn't have a .progressSummary case — the enum falls
        // back to .unknown for those rows — so we filter on display_hint
        // (macros_bar) which those records set reliably.
        let progressSummaryTarget: Double? = records
            .filter { $0.displayHint == .macrosBar }
            .filter { record in
                record.data.objectValue?["date"]?.stringValue == dateString
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?
            .data
            .objectValue?["target_calories"]?
            .numberValue

        if let progressSummaryTarget, progressSummaryTarget > 0 {
            targets.calories = progressSummaryTarget
        } else {
            // Fallback to legacy `daily_calories` measurement records. Kept so
            // environments still writing to the old path don't regress.
            let legacyTarget = records
                .compactMap { record -> (Record, MeasurementData)? in
                    guard let measurement = record.asMeasurement(), measurement.metric == "daily_calories" else {
                        return nil
                    }
                    return (record, measurement)
                }
                .filter { sample in
                    sample.1.context == dateString || sample.1.timestamp.map { calendar.isDate($0, inSameDayAs: date) } == true
                }
                .sorted { $0.0.updatedAt > $1.0.updatedAt }
                .first?
                .1
                .target

            if let legacyTarget, legacyTarget > 0 {
                targets.calories = legacyTarget
            }
        }

        let macros = records
            .compactMap { record -> (Record, MacrosData)? in
                guard let macros = record.asMacros() else { return nil }
                return (record, macros)
            }
            .filter { $0.1.date == dateString }
            .sorted { $0.0.updatedAt > $1.0.updatedAt }
            .first?
            .1

        if let proteinTarget = macros?.proteinTarget, proteinTarget > 0 {
            targets.protein = proteinTarget
        }
        if let carbsTarget = macros?.carbsTarget, carbsTarget > 0 {
            targets.carbs = carbsTarget
        }
        if let fatTarget = macros?.fatTarget, fatTarget > 0 {
            targets.fat = fatTarget
        }

        return targets
    }
}

struct DailyNutritionSummary: Sendable, Equatable {
    var consumed: NutritionTargets
    var targets: NutritionTargets

    static var empty: DailyNutritionSummary {
        DailyNutritionSummary(
            consumed: NutritionTargets(calories: 0, protein: 0, carbs: 0, fat: 0),
            targets: NutritionTargets()
        )
    }
}

struct NutritionDaySection: Identifiable, Sendable {
    let id: Date
    let date: Date
    let meals: [MealRecord]
    let summary: DailyNutritionSummary

    init(date: Date, meals: [MealRecord], targets: NutritionTargets = NutritionTargets()) {
        self.id = date
        self.date = date
        self.meals = meals

        let consumed = NutritionTargets(
            calories: meals.reduce(0) { $0 + $1.calories },
            protein: meals.reduce(0) { $0 + $1.protein },
            carbs: meals.reduce(0) { $0 + $1.carbs },
            fat: meals.reduce(0) { $0 + $1.fat }
        )

        self.summary = DailyNutritionSummary(consumed: consumed, targets: targets)
    }
}
