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
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self.handleAppRefresh(task: refreshTask)
        }
    }

    /// Schedule the next background refresh. Call after each foreground fetch completes.
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min minimum
        do {
            try BGTaskScheduler.shared.submit(request)
#if DEBUG
            print("[BGRefresh] Scheduled next refresh in ~15 min")
#endif
        } catch {
            #if DEBUG
            print("[BGRefresh] Failed to schedule: \(error)")
            #endif
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

                // Refuse to cache under a missing or wrong user — no auth, no write.
                guard let userId = service.currentUserId else {
#if DEBUG
                    print("[BGRefresh] No authenticated user, skipping refresh")
#endif
                    task.setTaskCompleted(success: false)
                    return
                }

                // Fetch records (the main data)
                let records = try await service.fetchRecords(limit: 200, forceRefresh: true)
                cacheService.saveRecords(records, category: nil, userId: userId)

                // Fetch sections
                let sections = try await service.fetchSections(forceRefresh: true)
                cacheService.saveSections(sections, userId: userId)

                // home_widgets fetch removed in Round 4 — table is empty
                // in production and no view consumes the array.
#if DEBUG
                print("[BGRefresh] Successfully refreshed \(records.count) records, \(sections.count) sections")
#endif
                task.setTaskCompleted(success: true)
            } catch {
                #if DEBUG
                print("[BGRefresh] Failed: \(error)")
                #endif
                task.setTaskCompleted(success: false)
            }
        }

        // If the system kills the task, cancel our fetch
        task.expirationHandler = {
            fetchTask.cancel()
        }
    }
}
