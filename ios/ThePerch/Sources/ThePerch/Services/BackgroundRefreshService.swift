import BackgroundTasks
import Foundation

/// Manages background app refresh to keep cached data fresh.
/// Registers a BGAppRefreshTask that fetches latest data from Supabase
/// so the next app open shows near-current data from cache.
@MainActor
final class BackgroundRefreshService {
    static let shared = BackgroundRefreshService()

    /// Task identifier - must match Info.plist BGTaskSchedulerPermittedIdentifiers
    static let refreshTaskId = "com.NotButter.ThePerch.refresh"

    private init() {}

    /// Register the background task handler. Call once at app startup.
    func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskId,
            using: nil
        ) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }

    /// Schedule the next background refresh. Call after each foreground fetch completes.
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min minimum
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BGRefresh] Scheduled next refresh in ~15 min")
        } catch {
            print("[BGRefresh] Failed to schedule: \(error)")
        }
    }

    /// Handle the background refresh task.
    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule next refresh before doing work
        scheduleAppRefresh()

        let fetchTask = Task {
            do {
                let service = SupabaseService.shared
                let cacheService = CacheService.shared
                let userId = "default_user"

                // Fetch records (the main data)
                let records = try await service.fetchRecords(limit: 200, forceRefresh: true)
                cacheService.saveRecords(records, category: nil, userId: userId)

                // Fetch sections
                let sections = try await service.fetchSections(forceRefresh: true)
                cacheService.saveSections(sections, userId: userId)

                // Fetch widgets (currently in-memory only; no disk cache API yet)
                let widgets = try await service.fetchHomeWidgets(forceRefresh: true)

                print("[BGRefresh] Successfully refreshed \(records.count) records, \(sections.count) sections, \(widgets.count) widgets")
                task.setTaskCompleted(success: true)
            } catch {
                print("[BGRefresh] Failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }

        // If the system kills the task, cancel our fetch
        task.expirationHandler = {
            fetchTask.cancel()
        }
    }
}
