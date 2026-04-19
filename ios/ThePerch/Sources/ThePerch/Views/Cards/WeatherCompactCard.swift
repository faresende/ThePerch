import SwiftUI

/// A compact single-row weather card showing current conditions.
/// Hides entirely when no weather data exists. Tapping opens wttr.in in Safari.
struct WeatherCompactCard: View {
    let records: [Record]
    @Environment(\.perchPalette) private var palette

    private var weather: WeatherData? {
        records.compactMap { record -> WeatherData? in
            guard record.category == .health || record.category == .admin,
                  record.title.localizedCaseInsensitiveContains("weather")
            else { return nil }
            return record.asWeather()
        }.first
    }

    private var bucket: PerchPhrase.WeatherBucket {
        guard let w = weather else { return .mild }
        let icon = w.icon
        if icon.contains("rain") || icon.contains("drizzle") { return .rain }
        if w.temperature >= 20 { return .warm }
        if w.temperature < 10 { return .cold }
        return .mild
    }

    var body: some View {
        if let w = weather {
            TodayCard {
                VStack(alignment: .leading, spacing: 0) {
                    TodayEyebrow(
                        label: "WEATHER · LONDON",
                        accent: palette.wellness,
                        freshness: "now"
                    )

                    HStack(alignment: .center, spacing: 16) {
                        Text("\(Int(w.temperature))°")
                            .font(PerchTheme.Font.tempNumeric)
                            .tracking(-1.2)
                            .foregroundColor(palette.ink)
                            .lineLimit(1)
                            .fixedSize()

                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.conditions)
                                .font(PerchTheme.Font.bodyRow)
                                .foregroundColor(palette.ink)
                                .lineLimit(1)

                            if let high = w.high, let low = w.low {
                                Text("H \(Int(high))° · L \(Int(low))°")
                                    .font(PerchTheme.Font.rowNumeric)
                                    .tracking(0.2)
                                    .foregroundColor(palette.muted)
                            }
                        }

                        Spacer(minLength: 0)
                    }

                    // Phrase (italic serif, below the temp row)
                    Text(PerchPhrase.weatherPhrase(bucket: bucket) + ".")
                        .font(.system(size: 14, design: .serif).italic())
                        .foregroundColor(palette.muted)
                        .lineSpacing(3)
                        .padding(.top, 12)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WeatherCompactCard(records: [])
        .padding(PerchTheme.Spacing.large)
        .background(PerchTheme.background)
}
