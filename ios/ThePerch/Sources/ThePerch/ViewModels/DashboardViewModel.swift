import Foundation
import Observation

// MARK: - DashboardViewModel

/// Manages the state of the main dashboard screen.
/// Handles sections, widgets, loading, and realtime updates.
@Observable
@MainActor
final class DashboardViewModel {
    // MARK: - Published Properties

    var sections: [Section] = []
    var homeWidgets: [HomeWidget] = []
    var isLoading: Bool = false
    var error: SupabaseServiceError?

    // MARK: - Private Properties

    private let supabaseService: SupabaseService

    // MARK: - Initialization

    init(supabaseService: SupabaseService = .shared) {
        self.supabaseService = supabaseService
    }

    // MARK: - Loading Data

    /// Loads the dashboard sections and widgets in parallel.
    func loadDashboard() async {
        isLoading = true
        defer { isLoading = false }

        // Fire both fetches in parallel — they're independent
        async let sectionsTask = supabaseService.fetchSections()
        async let widgetsTask = supabaseService.fetchHomeWidgets()

        do {
            let loadedSections = try await sectionsTask
            self.sections = loadedSections
            print("[DashboardVM] Loaded \(loadedSections.count) sections")
        } catch {
            print("[DashboardVM] fetchSections threw: \(error)")
            self.error = .unknownError(error.localizedDescription)
        }

        // Widgets are optional — don't let failure break the dashboard
        do {
            let loadedWidgets = try await widgetsTask
            self.homeWidgets = loadedWidgets
        } catch {
            print("[DashboardVM] fetchHomeWidgets threw: \(error)")
        }

        if self.error == nil {
            self.error = nil
        }
    }

    // MARK: - Section Management

    /// Reorders sections and persists the changes to the server.
    /// - Parameter reorderedSections: The sections in their new order.
    func reorderSections(_ reorderedSections: [Section]) async {
        var updatedSections = reorderedSections
        for index in updatedSections.indices {
            updatedSections[index].sortOrder = index
        }

        do {
            try await supabaseService.updateSectionOrder(sections: updatedSections)
            self.sections = updatedSections
            self.error = nil
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    /// Toggles the visibility of a section.
    /// - Parameter sectionId: The ID of the section to toggle.
    func toggleSectionVisibility(sectionId: UUID) async {
        guard let index = sections.firstIndex(where: { $0.id == sectionId }) else { return }

        sections[index].isVisible.toggle()

        do {
            try await supabaseService.updateSectionOrder(sections: sections)
            self.error = nil
        } catch let error as SupabaseServiceError {
            // Revert on failure
            sections[index].isVisible.toggle()
            self.error = error
        } catch {
            sections[index].isVisible.toggle()
            self.error = .unknownError(error.localizedDescription)
        }
    }

    // MARK: - Widget Management

    /// Updates the visibility and position of home widgets.
    /// - Parameter updatedWidgets: The updated widget configurations.
    func updateWidgets(_ updatedWidgets: [HomeWidget]) async {
        do {
            try await supabaseService.updateHomeWidgets(widgets: updatedWidgets)
            self.homeWidgets = updatedWidgets
            self.error = nil
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    // MARK: - Realtime Subscriptions

    /// Sets up realtime subscriptions to listen for dashboard changes.
    func setupRealtimeSubscriptions() async {
        do {
            try await supabaseService.subscribeToRecords { [weak self] _ in
                // TODO: Update sections based on new record data
                // This callback will be invoked whenever records change in realtime
            }

            try await supabaseService.subscribeToAgents { [weak self] _ in
                // TODO: Update agent information in realtime
                // This callback will be invoked whenever agents change in realtime
            }
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    // MARK: - Error Handling

    /// Clears any error messages.
    func clearError() {
        self.error = nil
    }
}
