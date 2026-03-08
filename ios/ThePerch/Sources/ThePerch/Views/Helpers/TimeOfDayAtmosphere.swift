import SwiftUI
import Combine

/// A nearly imperceptible 2-stop gradient overlay that shifts color based on time of day.
/// Updates once per minute. Applied as a background layer behind all content.
struct TimeOfDayAtmosphere: View {
    @State private var gradientColors: (Color, Color) = Self.colorsForCurrentTime()

    /// Timer publisher that fires once per minute
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        LinearGradient(
            colors: [gradientColors.0, gradientColors.1],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onReceive(timer) { _ in
            let newColors = Self.colorsForCurrentTime()
            PerchMotion.withOptionalAnimation(.easeInOut(duration: 2.0)) {
                gradientColors = newColors
            }
        }
    }

    // MARK: - Time Period Colors

    private enum TimePeriod {
        case morning    // 6-10am: warm golden
        case midday     // 10am-4pm: neutral
        case evening    // 4-10pm: cool blue-violet
        case night      // 10pm-6am: deep navy

        static func current(hour: Int) -> TimePeriod {
            switch hour {
            case 6..<10: return .morning
            case 10..<16: return .midday
            case 16..<22: return .evening
            default: return .night
            }
        }

        /// Top gradient color at ~4% opacity
        var topColor: Color {
            switch self {
            case .morning:
                return Color(red: 0.95, green: 0.75, blue: 0.3).opacity(0.04)
            case .midday:
                return Color(red: 0.9, green: 0.85, blue: 0.7).opacity(0.025)
            case .evening:
                return Color(red: 0.4, green: 0.35, blue: 0.75).opacity(0.04)
            case .night:
                return Color(red: 0.1, green: 0.12, blue: 0.3).opacity(0.05)
            }
        }

        /// Bottom gradient color at ~3% opacity
        var bottomColor: Color {
            switch self {
            case .morning:
                return Color(red: 0.9, green: 0.6, blue: 0.2).opacity(0.03)
            case .midday:
                return Color.clear
            case .evening:
                return Color(red: 0.3, green: 0.25, blue: 0.6).opacity(0.03)
            case .night:
                return Color(red: 0.05, green: 0.08, blue: 0.25).opacity(0.04)
            }
        }
    }

    private static func colorsForCurrentTime() -> (Color, Color) {
        let hour = Calendar.current.component(.hour, from: Date.now)
        let period = TimePeriod.current(hour: hour)
        return (period.topColor, period.bottomColor)
    }
}
