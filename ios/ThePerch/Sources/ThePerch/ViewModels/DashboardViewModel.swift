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
    func loadDashboard(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        // Fire both fetches in parallel
        async let sectionsResult: Result<[Section], Error> = {
            do { return .success(try await supabaseService.fetchSections(forceRefresh: forceRefresh)) }
            catch { return .failure(error) }
        }()
        async let widgetsResult: Result<[HomeWidget], Error> = {
            do { return .success(try await supabaseService.fetchHomeWidgets(forceRefresh: forceRefresh)) }
            catch { return .failure(error) }
        }()

        let (sections, widgets) = await (sectionsResult, widgetsResult)

        switch sections {
        case .success(let loaded):
            self.sections = loaded
            self.error = nil
        case .failure(let err):
            print("[DashboardVM] fetchSections threw: \(err)")
            self.error = .unknownError(err.localizedDescription)
        }

        if case .success(let loaded) = widgets {
            self.homeWidgets = loaded
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
    /// When records change, we re-fetch the relevant data to keep the UI fresh.
    func setupRealtimeSubscriptions() async {
        do {
            try await supabaseService.subscribeToRecords { [weak self] change in
                guard let self else { return }
                print("[DashboardVM] Realtime record change: \(change.action)")
                Task { @MainActor in
                    await self.loadDashboard()
                    if let record = change.record {
                        NotificationService.shared.handleRecordChange(record: record, action: change.action)
                    }
                }
            }

            try await supabaseService.subscribeToAgents { [weak self] action in
                guard let self else { return }
                print("[DashboardVM] Realtime agent change: \(action)")
                Task { @MainActor in
                    await self.loadDashboard()
                }
            }
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    /// Tears down realtime subscriptions.
    func teardownRealtimeSubscriptions() async {
        await supabaseService.unsubscribeAll()
    }

    // MARK: - Error Handling

    /// Clears any error messages.
    func clearError() {
        self.error = nil
    }
}
