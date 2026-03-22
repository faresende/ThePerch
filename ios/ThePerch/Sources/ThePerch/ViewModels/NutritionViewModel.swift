import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class NutritionViewModel {
    var meals: [Record] = []
    var isAnalyzing = false
    var error: String?

    private let nutritionService: NutritionService
    private let supabaseService: SupabaseServiceProtocol

    init(
        nutritionService: NutritionService = .shared,
        supabaseService: SupabaseServiceProtocol = SupabaseService.shared
    ) {
        self.nutritionService = nutritionService
        self.supabaseService = supabaseService
    }

    func loadMeals(from records: [Record]) {
        meals = records
            .filter { $0.category == .nutrition && $0.type == .meal }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func logMeal(text: String?, image: UIImage?, userId: String) async {
        isAnalyzing = true
        error = nil
        defer { isAnalyzing = false }

        do {
            let imageData = image?.jpegData(compressionQuality: 1.0)
            _ = try await nutritionService.analyzeMeal(text: text, imageData: imageData)
            _ = userId
            try await refreshMeals()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func correctMeal(recordId: String, correction: String) async {
        isAnalyzing = true
        error = nil
        defer { isAnalyzing = false }

        do {
            _ = try await nutritionService.correctMeal(recordId: recordId, correctionText: correction)
            try await refreshMeals()
        } catch {
            self.error = error.localizedDescription
        }
    }

    var dailySummary: DailyNutritionSummary {
        let calendar = Calendar.current
        let todayMeals = meals
            .map(MealRecord.init(from:))
            .filter { calendar.isDate($0.mealTime, inSameDayAs: .now) }

        let consumed = NutritionTargets(
            calories: todayMeals.reduce(0) { $0 + $1.calories },
            protein: todayMeals.reduce(0) { $0 + $1.protein },
            carbs: todayMeals.reduce(0) { $0 + $1.carbs },
            fat: todayMeals.reduce(0) { $0 + $1.fat }
        )

        return DailyNutritionSummary(
            consumed: consumed,
            targets: NutritionTargets()
        )
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
}
