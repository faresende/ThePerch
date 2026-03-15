import SwiftUI

/// A compact single-row weather card showing current conditions.
/// Hides entirely when no weather data exists. Tapping opens wttr.in in Safari.
struct WeatherCompactCard: View {
    let records: [Record]

    private var weather: WeatherData? {
        records.compactMap { record -> WeatherData? in
            guard record.category == .health || record.category == .admin,
                  record.title.localizedCaseInsensitiveContains("weather")
            else { return nil }
            return record.asWeather()
        }.first
    }

    var body: some View {
        if let w = weather {
            Button {
                if let url = URL(string: "https://wttr.in") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: PerchTheme.Spacing.small) {
                    // Weather icon + temperature
                    HStack(spacing: PerchTheme.Spacing.xSmall) {
                        Image(systemName: w.icon)
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(iconColor(for: w.icon))
                            .symbolRenderingMode(.multicolor)
                        Text("\(Int(w.temperature))°C")
                            .font(PerchTheme.Font.titleNumeric)
                            .foregroundColor(PerchTheme.textPrimary)
                    }

                    Text(w.conditions)
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    // Rain probability
                    if let rain = w.rainProbability, rain > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "cloud.rain.fill")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(.blue)
                            Text("\(Int(rain))%")
                                .font(PerchTheme.Font.captionMono)
                                .foregroundColor(PerchTheme.textSecondary)
                        }

                        divider
                    }

                    // High / Low
                    if let high = w.high, let low = w.low {
                        HStack(spacing: 4) {
                            Text("H:\(Int(high))°")
                                .font(PerchTheme.Font.captionMono)
                                .foregroundColor(PerchTheme.textSecondary)
                            Text("L:\(Int(low))°")
                                .font(PerchTheme.Font.captionMono)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(PerchTheme.textTertiary)
                }
                .padding(.horizontal, PerchTheme.Card.padding)
                .padding(.vertical, PerchTheme.Spacing.medium)
                .cardStyle()
                .contentShape(Rectangle())
            }
            .buttonStyle(CardPressStyle())
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(PerchTheme.border)
            .frame(width: 1, height: 20)
    }

    private func iconColor(for icon: String) -> Color {
        if icon.contains("sun") { return .yellow }
        if icon.contains("cloud.rain") || icon.contains("cloud.drizzle") { return .blue }
        if icon.contains("cloud") { return .gray }
        if icon.contains("snow") { return .white }
        if icon.contains("wind") { return .teal }
        return PerchTheme.textSecondary
    }
}

// MARK: - Preview

#Preview {
    WeatherCompactCard(records: [])
        .padding(PerchTheme.Spacing.large)
        .background(PerchTheme.background)
}
