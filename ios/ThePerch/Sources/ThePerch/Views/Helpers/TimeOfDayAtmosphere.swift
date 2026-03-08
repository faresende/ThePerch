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
                return Color(red: 0.949, green: 0.690, blue: 0.290).opacity(0.035) // amber whisper
            case .midday:
                return Color(red: 0.95, green: 0.92, blue: 0.86).opacity(0.020) // warm near-clear
            case .evening:
                return Color(red: 0.655, green: 0.678, blue: 0.714).opacity(0.030) // steel whisper
            case .night:
                return Color(red: 0.10, green: 0.12, blue: 0.18).opacity(0.045) // steel-navy
            }
        }

        /// Bottom gradient color at ~3% opacity
        var bottomColor: Color {
            switch self {
            case .morning:
                return Color(red: 0.949, green: 0.690, blue: 0.290).opacity(0.025)
            case .midday:
                return Color.clear
            case .evening:
                return Color(red: 0.40, green: 0.44, blue: 0.52).opacity(0.022)
            case .night:
                return Color(red: 0.05, green: 0.07, blue: 0.12).opacity(0.040)
            }
        }
    }

    private static func colorsForCurrentTime() -> (Color, Color) {
        let hour = Calendar.current.component(.hour, from: Date.now)
        let period = TimePeriod.current(hour: hour)
        return (period.topColor, period.bottomColor)
    }
}
