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

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        let fallbackFormatter = ISO8601DateFormatter()
        if let date = fallbackFormatter.date(from: string) {
            return date
        }

        return PerchFormatters.iso8601.date(from: string)
    }
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

struct NutritionTargets: Sendable {
    var calories: Double = 3000
    var protein: Double = 180
    var carbs: Double = 250
    var fat: Double = 80
}

struct DailyNutritionSummary: Sendable {
    var consumed: NutritionTargets
    var targets: NutritionTargets
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
