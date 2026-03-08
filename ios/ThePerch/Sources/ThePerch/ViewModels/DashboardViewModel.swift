import Foundation
import Observation

// MARK: - DashboardViewModel

/// Manages the state of the main dashboard screen.
/// Single source of truth for ALL records — fetches once, distributes to sections.
/// Also handles sections, widgets, loading, and realtime updates.
@Observable
@MainActor
final class DashboardViewModel {
    // MARK: - Published Properties

    var sections: [Section] = []
    var homeWidgets: [HomeWidget] = []
    var isLoading: Bool = false
    var error: SupabaseServiceError?

    /// Single source of truth: ALL records fetched in one request.
    var allRecords: [Record] = []

    /// Agents are fetched separately (different table, admin-only).
    var agents: [Agent] = []

    // MARK: - Filtered Record Properties

    var healthRecords: [Record] { allRecords.filter { $0.category == .health } }
    var deliveryRecords: [Record] { allRecords.filter { $0.category == .deliveries } }
    var calendarRecords: [Record] { allRecords.filter { $0.category == .calendar } }
    var adminRecords: [Record] { allRecords.filter { $0.category == .admin } }
    var bookmarkRecords: [Record] { allRecords.filter { $0.category == .bookmarks } }

    // MARK: - Private Properties

    private let supabaseService: SupabaseService

    // MARK: - Initialization

    init(supabaseService: SupabaseService = .shared) {
        self.supabaseService = supabaseService
    }

    // MARK: - Loading Data

    /// Loads the dashboard: sections, widgets, and ALL records in parallel.
    func loadDashboard(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        // Fire all fetches in parallel
        async let sectionsResult: Result<[Section], Error> = {
            do { return .success(try await supabaseService.fetchSections(forceRefresh: forceRefresh)) }
            catch { return .failure(error) }
        }()
        async let widgetsResult: Result<[HomeWidget], Error> = {
            do { return .success(try await supabaseService.fetchHomeWidgets(forceRefresh: forceRefresh)) }
            catch { return .failure(error) }
        }()
        async let recordsResult: Result<[Record], Error> = {
            do { return .success(try await supabaseService.fetchRecords(limit: 200, forceRefresh: forceRefresh)) }
            catch { return .failure(error) }
        }()

        let (sections, widgets, records) = await (sectionsResult, widgetsResult, recordsResult)

        switch sections {
        case .success(let loaded):
            self.sections = loaded
            self.error = nil
        case .failure(let err):
            print("[DashboardVM] fetchSections threw: \(err)")
            self.error = .unknownError(err.localizedDescription)
        }

        switch widgets {
        case .success(let loaded):
            self.homeWidgets = loaded
        case .failure(let err):
            print("[DashboardVM] fetchHomeWidgets threw: \(err)")
            if self.error == nil {
                self.error = .unknownError(err.localizedDescription)
            }
        }

        switch records {
        case .success(let loaded):
            self.allRecords = loaded
        case .failure(let err):
            print("[DashboardVM] fetchRecords threw: \(err)")
            if self.error == nil {
                self.error = .unknownError(err.localizedDescription)
            }
        }
    }

    /// Refreshes only records (lighter than full loadDashboard).
    func refreshRecords(forceRefresh: Bool = true) async {
        do {
            allRecords = try await supabaseService.fetchRecords(limit: 200, forceRefresh: forceRefresh)
        } catch {
            print("[DashboardVM] refreshRecords threw: \(error)")
        }
    }

    /// Fetches agents separately (different table, admin-only).
    func loadAgents(forceRefresh: Bool = false) async {
        do {
            agents = try await supabaseService.fetchAgents(forceRefresh: forceRefresh)
        } catch {
            print("[DashboardVM] fetchAgents threw: \(error)")
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

    // MARK: - Record Actions

    /// Toggles the pinned state of a record.
    func toggleRecordPin(recordId: UUID) async {
        guard let index = allRecords.firstIndex(where: { $0.id == recordId }) else { return }

        let newPinnedState = !allRecords[index].pinned
        do {
            try await supabaseService.updateRecordPin(id: recordId, pinned: newPinnedState)
            allRecords[index].pinned = newPinnedState
        } catch {
            print("[DashboardVM] toggleRecordPin failed: \(error)")
        }
    }

    // MARK: - Realtime Subscriptions

    private let reconnectManager = RealtimeReconnectManager.shared

    /// Sets up realtime subscriptions to listen for dashboard changes.
    /// When records change, we re-fetch records to keep the UI fresh.
    func setupRealtimeSubscriptions() async {
        do {
            try await supabaseService.subscribeToRecords { [weak self] change in
                guard let self else { return }
                print("[DashboardVM] Realtime record change: \(change.action)")
                Task { @MainActor in
                    await self.refreshRecords()
                    if let record = change.record {
                        NotificationService.shared.handleRecordChange(record: record, action: change.action)
                        if record.category == .deliveries {
                            self.syncDeliveryLiveActivities()
                        }
                    }
                }
            }

            try await supabaseService.subscribeToAgents { [weak self] action in
                guard let self else { return }
                print("[DashboardVM] Realtime agent change: \(action)")
                Task { @MainActor in
                    await self.loadAgents(forceRefresh: true)
                }
            }

            reconnectManager.didConnect()
        } catch let error as SupabaseServiceError {
            self.error = error
            reconnectManager.didDisconnect { [weak self] in
                await self?.attemptRealtimeReconnect() ?? false
            }
        } catch {
            self.error = .unknownError(error.localizedDescription)
            reconnectManager.didDisconnect { [weak self] in
                await self?.attemptRealtimeReconnect() ?? false
            }
        }
    }

    /// Attempts to re-establish realtime subscriptions. Returns true on success.
    func attemptRealtimeReconnect() async -> Bool {
        do {
            await supabaseService.unsubscribeAll()
            try await supabaseService.subscribeToRecords { [weak self] change in
                guard let self else { return }
                Task { @MainActor in
                    await self.refreshRecords()
                    if let record = change.record {
                        NotificationService.shared.handleRecordChange(record: record, action: change.action)
                    }
                }
            }
            try await supabaseService.subscribeToAgents { [weak self] action in
                guard let self else { return }
                Task { @MainActor in
                    await self.loadAgents(forceRefresh: true)
                }
            }
            return true
        } catch {
            print("[DashboardVM] Realtime reconnect failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Tears down realtime subscriptions.
    func teardownRealtimeSubscriptions() async {
        await supabaseService.unsubscribeAll()
    }

    // MARK: - Live Activity Sync

    /// Syncs Live Activities using already-loaded delivery records.
    private func syncDeliveryLiveActivities() {
        let activeDeliveries = deliveryRecords.compactMap { record -> DeliveryData? in
            guard let d = record.asDelivery() else { return nil }
            let s = d.status.lowercased().replacingOccurrences(of: " ", with: "_")
            guard s == "in_transit" || s == "shipped" || s == "out_for_delivery" || s == "processing" || s == "ordered" else { return nil }
            return d
        }
        Task {
            await DeliveryLiveActivityManager.shared.sync(activeDeliveries: activeDeliveries)
        }
    }

    // MARK: - Error Handling

    /// Clears any error messages.
    func clearError() {
        self.error = nil
    }
}
