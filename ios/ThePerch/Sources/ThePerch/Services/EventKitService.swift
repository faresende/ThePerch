import Foundation
import EventKit

// MARK: - Error Types

/// Errors that can occur during EventKit operations.
enum EventKitServiceError: LocalizedError {
    case permissionDenied(String)
    case eventKitError(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let message):
            return "Permission denied: \(message)"
        case .eventKitError(let message):
            return "EventKit error: \(message)"
        }
    }
}

// MARK: - EventKit Wrappers

/// A simple wrapper around EKEvent for use in the app.
struct EventKitEvent: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let notes: String?

    init(ekEvent: EKEvent) {
        self.id = ekEvent.eventIdentifier
        self.title = ekEvent.title
        self.startDate = ekEvent.startDate
        self.endDate = ekEvent.endDate
        self.location = ekEvent.location
        self.notes = ekEvent.notes
    }
}

/// A simple wrapper around EKReminder for use in the app.
struct EventKitReminder: Identifiable {
    let id: String
    let title: String
    let dueDate: Date?
    let isCompleted: Bool
    let list: String?
    let notes: String?

    init(ekReminder: EKReminder) {
        self.id = ekReminder.calendarItemIdentifier
        self.title = ekReminder.title
        self.dueDate = ekReminder.dueDateComponents?.date
        self.isCompleted = ekReminder.isCompleted
        self.list = ekReminder.calendar?.title
        self.notes = ekReminder.notes
    }
}

// MARK: - EventKitService

/// Service for interacting with the device's EventKit calendar and reminders.
/// Fetches local calendar events and reminders, but does not sync to Supabase.
/// Not @MainActor — performs IO work; only ViewModels should be @MainActor.
final class EventKitService: NSObject, @unchecked Sendable {
    static let shared = EventKitService()

    private let eventStore = EKEventStore()

    // MARK: - Permissions

    /// Requests permission to access the calendar.
    /// - Returns: True if permission was granted or already available.
    func requestCalendarPermission() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .fullAccess, .writeOnly:
            return true
        case .notDetermined:
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                return false
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Requests permission to access reminders.
    /// - Returns: True if permission was granted or already available.
    func requestRemindersPermission() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .fullAccess:
            return true
        case .notDetermined:
            do {
                return try await eventStore.requestFullAccessToReminders()
            } catch {
                return false
            }
        case .denied, .restricted, .writeOnly:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Fetching Events

    /// Fetches upcoming events from the specified calendars.
    func fetchUpcomingEvents(
        days: Int = 7,
        calendarNames: [String]? = nil
    ) async throws -> [EventKitEvent] {
        let hasPermission = await requestCalendarPermission()
        guard hasPermission else {
            throw EventKitServiceError.permissionDenied("Calendar access not granted")
        }

        let now = Date.now
        let endDate = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now

        var calendars: [EKCalendar]? = nil
        if let calendarNames, !calendarNames.isEmpty {
            calendars = eventStore.calendars(for: .event).filter { calendar in
                calendarNames.contains(calendar.title)
            }
        }

        let predicate = eventStore.predicateForEvents(withStart: now, end: endDate, calendars: calendars)
        let ekEvents = eventStore.events(matching: predicate)

        return ekEvents
            .map { EventKitEvent(ekEvent: $0) }
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Fetching Reminders

    /// Fetches reminders from the specified lists.
    func fetchReminders(
        includeCompleted: Bool = false,
        listNames: [String]? = nil
    ) async throws -> [EventKitReminder] {
        let hasPermission = await requestRemindersPermission()
        guard hasPermission else {
            throw EventKitServiceError.permissionDenied("Reminders access not granted")
        }

        var calendars: [EKCalendar]? = nil
        if let listNames, !listNames.isEmpty {
            calendars = eventStore.calendars(for: .reminder).filter { calendar in
                listNames.contains(calendar.title)
            }
        }

        let predicate = includeCompleted
            ? eventStore.predicateForReminders(in: calendars)
            : eventStore.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: calendars
            )

        // Bridge the completion-handler API to async
        let ekReminders: [EKReminder] = try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }

        return ekReminders
            .map { EventKitReminder(ekReminder: $0) }
            .sorted { reminder1, reminder2 in
                guard let date1 = reminder1.dueDate else { return false }
                guard let date2 = reminder2.dueDate else { return true }
                return date1 < date2
            }
    }

    // MARK: - Available Calendars & Lists

    /// Returns the titles of all available calendars.
    func getAvailableCalendars() -> [String] {
        eventStore.calendars(for: .event).map { $0.title }
    }

    /// Returns the titles of all available reminder lists.
    func getAvailableReminderLists() -> [String] {
        eventStore.calendars(for: .reminder).map { $0.title }
    }
}
