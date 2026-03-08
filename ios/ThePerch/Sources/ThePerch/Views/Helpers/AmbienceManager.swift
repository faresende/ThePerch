import SwiftUI
import Observation
import Combine

/// Provides time-of-day ambient color tinting for the Home screen.
/// Updates every minute and when the app foregrounds.
/// Colors are subtle tints — ambient, not a theme change.
@Observable
@MainActor
final class AmbienceManager {
    static let shared = AmbienceManager()

    // MARK: - Published State

    private(set) var ambientColor: Color = AmbienceManager.colorForCurrentHour()
    private(set) var period: HomeCardOrdering.TimePeriod = .current
    private(set) var sfSymbol: String = AmbienceManager.symbolForCurrentHour()

    // MARK: - Private

    private var timer: Timer?
    private var foregroundObserver: Any?

    private init() {
        startTimer()
        observeForeground()
    }

    deinit {
        timer?.invalidate()
        if let obs = foregroundObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func observeForeground() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        let newColor = Self.colorForCurrentHour()
        let newPeriod = HomeCardOrdering.TimePeriod.current
        let newSymbol = Self.symbolForCurrentHour()
        if period != newPeriod {
            withAnimation(.easeInOut(duration: 1.0)) {
                ambientColor = newColor
                period = newPeriod
                sfSymbol = newSymbol
            }
        } else {
            ambientColor = newColor
            sfSymbol = newSymbol
        }
    }

    // MARK: - Color Mapping

    static func colorForCurrentHour() -> Color {
        let hour = Calendar.current.component(.hour, from: .now)
        return colorForHour(hour)
    }

    static func colorForHour(_ hour: Int) -> Color {
        switch hour {
        case 6..<12:
            // Morning: warm gold #FFB74D
            return Color(red: 1.0, green: 0.718, blue: 0.302)
        case 12..<17:
            // Afternoon: bright blue #42A5F5
            return Color(red: 0.259, green: 0.647, blue: 0.961)
        case 17..<22:
            // Evening: soft purple #AB47BC
            return Color(red: 0.671, green: 0.278, blue: 0.737)
        default:
            // Night (22-06): deep indigo #5C6BC0
            return Color(red: 0.361, green: 0.420, blue: 0.753)
        }
    }

    static func symbolForCurrentHour() -> String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 6..<12: return "sun.horizon.fill"
        case 12..<17: return "sun.max.fill"
        case 17..<22: return "moon.haze.fill"
        default: return "moon.stars.fill"
        }
    }
}
