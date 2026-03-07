import Foundation

/// Utility functions for formatting dates and durations.
enum DateFormatting {
    /// Formats a date as a relative time string (e.g., "2 hours ago").
    static func relativeTime(from date: Date) -> String {
        let interval = Date.now.timeIntervalSince(date)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 {
            return "now"
        } else if minutes < 60 {
            return "\(minutes)m ago"
        } else if hours < 24 {
            return "\(hours)h ago"
        } else if days < 7 {
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }

    /// Formats a date as a short date string (e.g., "Mar 15, 2026").
    static func shortDate(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Formats a date as a full date and time string.
    static func fullDateTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Formats a time interval (in seconds) as a human-readable duration.
    static func duration(from interval: TimeInterval) -> String {
        let seconds = Int(interval)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24

        if days > 0 {
            return "\(days) day\(days == 1 ? "" : "s")"
        } else if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else if minutes > 0 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            return "\(seconds) second\(seconds == 1 ? "" : "s")"
        }
    }

    /// Formats an uptime value (in hours) as a human-readable string.
    static func uptimeString(from hours: Double) -> String {
        let days = Int(hours / 24)
        let remainingHours = Int(hours) % 24

        if days > 0 {
            return "\(days)d \(remainingHours)h"
        } else {
            return "\(Int(hours))h"
        }
    }
}
