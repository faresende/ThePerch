import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class NutritionViewModel {
    /// Setting `meals` recomputes `daySections`. Round 9 audit caught
    /// the prior computed-property version doing a Dictionary(grouping:)
    /// + 3 sorts on every read — and several body paths read it 3×
    /// per render. Now cached and recomputed only when meals change.
    var meals: [Record] = [] {
        didSet { recomputeDaySections() }
    }
    var visibleDayCount = 7
    var mealSuggestions: [MealSuggestion] = []
    var isAnalyzing = false
    var isLoadingSuggestions = false
    var error: String?

    /// Cached projection of `meals` into per-day sections with target macros.
    private(set) var daySections: [NutritionDaySection] = []

    private let nutritionService: NutritionService
    private let supabaseService: SupabaseServiceProtocol
    private let pageSize = 7
    /// Set BEFORE `meals` in `loadMeals(from:)` so the meals didSet
    /// picks up fresh targets — no double-recompute.
    private var targetSourceRecords: [Record] = []

    /// Default arguments are `nil` so we don't reference `@MainActor`
    /// singletons from the (potentially nonisolated) caller's context.
    /// The class itself is `@MainActor`, so the init body executes on
    /// MainActor and can safely resolve the singletons there.
    init(
        nutritionService: NutritionService? = nil,
        supabaseService: SupabaseServiceProtocol? = nil
    ) {
        self.nutritionService = nutritionService ?? .shared
        self.supabaseService = supabaseService ?? SupabaseService.shared
    }

    func loadMeals(from records: [Record]) {
        let containsTargetContext = records.contains {
            $0.asMeasurement()?.metric == "daily_calories" || $0.asMacros() != nil
        }
        if containsTargetContext || targetSourceRecords.isEmpty {
            targetSourceRecords = records
        }

        meals = records
            .filter { $0.category == .nutrition && $0.type == .meal }
            .sorted { $0.createdAt > $1.createdAt }

        let availableDays = daySections.count
        if availableDays > 0 {
            visibleDayCount = min(max(visibleDayCount, pageSize), availableDays)
        } else {
            visibleDayCount = pageSize
        }
    }

    @discardableResult
    func logMeal(text: String?, image: UIImage?, userId: String) async -> Bool {
        isAnalyzing = true
        error = nil
        defer { isAnalyzing = false }

        do {
            let imageData = image?.jpegData(compressionQuality: 1.0)
            _ = try await nutritionService.analyzeMeal(text: text, imageData: imageData, userId: userId)
            try await refreshMeals()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func correctMeal(recordId: String, correction: String) async {
        guard correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }

        isAnalyzing = true
        error = nil
        markMealCorrected(recordId: recordId)
        defer { isAnalyzing = false }

        do {
            _ = try await nutritionService.correctMeal(recordId: recordId, correctionText: correction)
            try await refreshMeals()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateMealMacros(
        recordId: UUID,
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    ) async {
        isAnalyzing = true
        error = nil

        updateMeal(
            recordId: recordId,
            mealName: nil,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            analysis: nil,
            corrected: true
        )

        defer { isAnalyzing = false }

        guard var data = meals.first(where: { $0.id == recordId })?.data.objectValue else {
            error = "Unable to find meal to update."
            return
        }

        data["calories"] = .number(calories)
        data["protein"] = .number(protein)
        data["carbs"] = .number(carbs)
        data["fat"] = .number(fat)
        data["corrected"] = .bool(true)

        do {
            try await supabaseService.updateRecordData(recordId: recordId, data: data)
            try await refreshMeals()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func requestSuggestions(userId: String, context: String?) async {
        isLoadingSuggestions = true
        error = nil
        defer { isLoadingSuggestions = false }

        do {
            let response = try await nutritionService.suggestMeals(userId: userId, context: context)
            mealSuggestions = try nutritionService.decodeSuggestions(from: response)
        } catch {
            self.error = error.localizedDescription
            mealSuggestions = []
        }
    }

    @discardableResult
    func logSuggestedMeal(_ suggestion: MealSuggestion, userId: String) async -> Bool {
        error = nil

        guard let userUUID = UUID(uuidString: userId) else {
            error = "You must be signed in to log a suggested meal."
            return false
        }

        do {
            try await supabaseService.insertRecord(
                agentId: "nutrition",
                userId: userUUID,
                type: .meal,
                category: .nutrition,
                title: suggestion.mealName,
                data: [
                    "meal_name": .string(suggestion.mealName),
                    "calories": .number(suggestion.calories),
                    "protein": .number(suggestion.protein),
                    "carbs": .number(suggestion.carbs),
                    "fat": .number(suggestion.fat),
                    "analysis": .string(suggestion.analysisLine),
                    "corrected": .bool(false),
                    "meal_time": .string(PerchFormatters.iso8601.string(from: .now)),
                ],
                displayHint: .unknown
            )
            try await refreshMeals()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func clearSuggestions() {
        mealSuggestions = []
    }

    func loadHistoryIfNeeded(for date: Date) {
        guard let lastVisibleDate = visibleSections.last?.date else { return }
        guard Calendar.current.isDate(date, inSameDayAs: lastVisibleDate) else { return }
        loadHistory()
    }

    func loadHistory() {
        let totalDays = daySections.count
        guard visibleDayCount < totalDays else { return }
        visibleDayCount = min(visibleDayCount + pageSize, totalDays)
    }

    private func recomputeDaySections() {
        let calendar = Calendar.current
        // Spell out the closure (rather than `meals.map(MealRecord.init(from:))`)
        // so Swift 6 inherits the enclosing MainActor isolation. The unapplied
        // initializer reference gets inferred as nonisolated, which conflicts
        // with `MealRecord.init(from:)` reading MainActor-isolated JSONValue
        // accessors.
        let groupedMeals = Dictionary(grouping: meals.map { MealRecord(from: $0) }) { meal in
            calendar.startOfDay(for: meal.mealTime)
        }

        var dates = groupedMeals.keys.sorted(by: >)
        let today = calendar.startOfDay(for: .now)
        if !dates.contains(today) {
            dates.insert(today, at: 0)
        }

        daySections = dates
            .sorted(by: >)
            .map { date in
                let mealsForDay = groupedMeals[date, default: []]
                    .sorted { $0.mealTime > $1.mealTime }
                return NutritionDaySection(
                    date: date,
                    meals: mealsForDay,
                    targets: NutritionTargets.resolved(for: date, records: targetSourceRecords)
                )
            }
    }

    var visibleSections: [NutritionDaySection] {
        Array(daySections.prefix(visibleDayCount))
    }

    var dailySummary: DailyNutritionSummary {
        visibleSections.first?.summary ?? .empty
    }

    private func refreshMeals() async throws {
        let records = try await supabaseService.fetchRecords(
            category: .nutrition,
            type: .meal,
            limit: 100,
            forceRefresh: true
        )
        loadMeals(from: records)
    }

    private func markMealCorrected(recordId: String) {
        guard let uuid = UUID(uuidString: recordId) else { return }
        updateMeal(
            recordId: uuid,
            mealName: nil,
            calories: nil,
            protein: nil,
            carbs: nil,
            fat: nil,
            analysis: nil,
            corrected: true
        )
    }

    private func updateMeal(
        recordId: UUID,
        mealName: String?,
        calories: Double?,
        protein: Double?,
        carbs: Double?,
        fat: Double?,
        analysis: String?,
        corrected: Bool?
    ) {
        guard let index = meals.firstIndex(where: { $0.id == recordId }) else { return }
        let record = meals[index]
        var data = record.data.objectValue ?? [:]

        if let mealName {
            data["meal_name"] = .string(mealName)
        }
        if let calories {
            data["calories"] = .number(calories)
        }
        if let protein {
            data["protein"] = .number(protein)
        }
        if let carbs {
            data["carbs"] = .number(carbs)
        }
        if let fat {
            data["fat"] = .number(fat)
        }
        if let analysis {
            data["analysis"] = .string(analysis)
        }
        if let corrected {
            data["corrected"] = .bool(corrected)
        }

        meals[index] = Record(
            id: record.id,
            agentId: record.agentId,
            userId: record.userId,
            type: record.type,
            category: record.category,
            title: mealName ?? record.title,
            data: .object(data),
            displayHint: record.displayHint,
            annotations: record.annotations,
            pinned: record.pinned,
            createdAt: record.createdAt,
            updatedAt: .now,
            expiresAt: record.expiresAt
        )
    }
}
