import SwiftUI

/// The dashboard-of-dashboards (first swipeable page).
/// Displays widget cards showing highlights from all sections.
struct HomeView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var showSettings = false
    @State private var records: [Record] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    // Header with greeting and settings
                    HStack {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                            Text(greetingText)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(PerchTheme.textSecondary)

                            Text("Fabio")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(PerchTheme.textPrimary)
                        }

                        Spacer()

                        Button(action: { showSettings = true }) {
                            Image(systemName: "gear")
                                .font(.system(size: 22))
                                .foregroundColor(PerchTheme.textSecondary)
                                .frame(width: 40, height: 40)
                                .background(PerchTheme.cardBackground)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, PerchTheme.Spacing.large)
                    .padding(.top, PerchTheme.Spacing.medium)

                    if isLoading {
                        ProgressView()
                            .tint(PerchTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else if records.isEmpty {
                        VStack(spacing: PerchTheme.Spacing.medium) {
                            Image(systemName: "tray")
                                .font(.system(size: 48))
                                .foregroundColor(PerchTheme.textTertiary)
                            Text("No data yet")
                                .font(PerchTheme.Font.headline)
                                .foregroundColor(PerchTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        // Highlights from across sections
                        VStack(spacing: PerchTheme.Spacing.medium) {
                            // Today's calories — pick the daily_calories record whose
                            // context matches today's date, or fall back to the most recent one
                            if let caloriesRecord = todaysCaloriesRecord {
                                WidgetRouter(record: caloriesRecord)
                            }

                            // Upcoming event (nearest future)
                            if let event = records.first(where: { $0.type == .event }) {
                                WidgetRouter(record: event)
                            }

                            // Active deliveries
                            ForEach(records.filter({
                                guard let d = $0.asDelivery() else { return false }
                                let s = d.status.lowercased()
                                return s != "delivered" && s != "cancelled"
                            })) { record in
                                WidgetRouter(record: record)
                            }

                            // Bookmark
                            if let bookmark = records.first(where: { $0.type == .bookmark }) {
                                WidgetRouter(record: bookmark)
                            }

                            // Checklist
                            if let checklist = records.first(where: { $0.type == .checklist }) {
                                WidgetRouter(record: checklist)
                            }

                            // Cost breakdown
                            if let cost = records.first(where: { $0.type == .costSummary }) {
                                WidgetRouter(record: cost)
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    // Bottom padding
                    Spacer()
                        .frame(height: PerchTheme.Spacing.large)
                }
            }
            .refreshable {
                await loadData()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        // Dashboard is already loaded by MainTabView — no need to reload here.
        // Just fetch the records for the home highlights.
        do {
            records = try await SupabaseService.shared.fetchRecords(limit: 50)
        } catch {
            print("[HomeView] Failed to load records: \(error)")
            records = []
        }
    }

    /// Find today's daily_calories record by matching the `context` field (date string like "2026-03-06")
    /// or fall back to the most recent one.
    private var todaysCaloriesRecord: Record? {
        let caloriesRecords = records.filter { $0.asMeasurement()?.metric == "daily_calories" }
        let todayString = {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            return fmt.string(from: Date.now)
        }()
        // Claudinho stores the date in the context field (e.g. "2026-03-06")
        if let today = caloriesRecords.first(where: { $0.asMeasurement()?.context == todayString }) {
            return today
        }
        // Fall back to most recent by timestamp or createdAt
        return caloriesRecords.sorted {
            let d0 = $0.asMeasurement()?.timestamp ?? $0.createdAt
            let d1 = $1.asMeasurement()?.timestamp ?? $1.createdAt
            return d0 > d1
        }.first
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date.now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environment(DashboardViewModel())
}
