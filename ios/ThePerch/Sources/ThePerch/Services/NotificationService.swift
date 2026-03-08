import Foundation
import Combine
import UserNotifications

/// Manages local notification scheduling and permissions.
/// Handles delivery status changes and calendar event reminders.
@MainActor
final class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published var isAuthorized: Bool = false
    @Published var permissionRequested: Bool = false

    private let center = UNUserNotificationCenter.current()
    private var initTask: Task<Void, Never>?

    private init() {
        initTask = Task { [weak self] in
            await self?.checkAuthorizationStatus()
        }
    }

    // MARK: - Permissions

    /// Requests notification permission from the user.
    func requestPermission() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            self.isAuthorized = granted
            self.permissionRequested = true
            print("[NotificationService] Permission granted: \(granted)")
        } catch {
            print("[NotificationService] Permission request failed: \(error)")
            self.isAuthorized = false
            self.permissionRequested = true
        }
    }

    /// Checks the current authorization status.
    func checkAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        self.isAuthorized = settings.authorizationStatus == .authorized
        self.permissionRequested = settings.authorizationStatus != .notDetermined
    }

    // MARK: - Delivery Notifications

    /// Schedules a notification for a delivery status change.
    func scheduleDeliveryNotification(deliveryData: DeliveryData, recordId: UUID) {
        guard isAuthorized else { return }

        let status = deliveryData.status.lowercased().replacingOccurrences(of: " ", with: "_")
        let itemName = deliveryData.items.first?.name ?? "Package"

        let content = UNMutableNotificationContent()
        content.sound = .default

        switch status {
        case "out_for_delivery":
            content.title = "Out for Delivery"
            content.body = "\(itemName) via \(deliveryData.carrier) is out for delivery!"
            content.categoryIdentifier = "DELIVERY_UPDATE"
        case "delivered":
            content.title = "Delivered!"
            content.body = "\(itemName) via \(deliveryData.carrier) has been delivered."
            content.categoryIdentifier = "DELIVERY_UPDATE"
        default:
            return // Only notify for these two statuses
        }

        let identifier = "delivery-\(recordId.uuidString)-\(status)"

        // Fire immediately (1 second delay)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                print("[NotificationService] Failed to schedule delivery notification: \(error)")
            } else {
                print("[NotificationService] Scheduled delivery notification: \(identifier)")
            }
        }
    }

    // MARK: - Calendar Reminders

    /// Schedules a reminder notification 30 minutes before a calendar event.
    func scheduleEventReminder(eventData: EventData, recordId: UUID) {
        guard isAuthorized else { return }

        let reminderTime = eventData.start.addingTimeInterval(-30 * 60) // 30 min before
        let now = Date.now

        // Only schedule if the reminder time is in the future
        guard reminderTime > now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Upcoming Event"
        content.body = "\(eventData.title) starts in 30 minutes"
        if let location = eventData.location, !location.isEmpty {
            content.body += " at \(location)"
        }
        content.sound = .default
        content.categoryIdentifier = "EVENT_REMINDER"

        let interval = reminderTime.timeIntervalSince(now)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
        let identifier = "event-\(recordId.uuidString)"

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                print("[NotificationService] Failed to schedule event reminder: \(error)")
            } else {
                print("[NotificationService] Scheduled event reminder: \(identifier) in \(Int(interval / 60))m")
            }
        }
    }

    // MARK: - Record Change Handler

    /// Handles a realtime record change and schedules appropriate notifications.
    func handleRecordChange(record: Record, action: SupabaseService.RealtimeAction) {
        guard action == .insert || action == .update else { return }

        // Delivery notifications
        if let delivery = record.asDelivery() {
            scheduleDeliveryNotification(deliveryData: delivery, recordId: record.id)
        }

        // Calendar event reminders
        if let event = record.asEvent() {
            scheduleEventReminder(eventData: event, recordId: record.id)
        }
    }

    // MARK: - Batch Scheduling

    /// Schedules reminders for all upcoming events in a set of records.
    func scheduleRemindersForRecords(_ records: [Record]) {
        guard isAuthorized else { return }

        // Cancel existing event reminders before re-scheduling
        let eventIds = records.filter { $0.type == .event }.map { "event-\($0.id.uuidString)" }
        if !eventIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: eventIds)
        }

        for record in records {
            if let event = record.asEvent() {
                scheduleEventReminder(eventData: event, recordId: record.id)
            }
        }
    }

    /// Cancels all pending notifications.
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        print("[NotificationService] Cancelled all pending notifications")
    }
}
