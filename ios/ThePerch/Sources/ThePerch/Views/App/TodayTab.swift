import SwiftUI
import AVKit

/// Today tab — The Perch's editorial front page (Linen / Variant A).
/// Full-bleed time-of-day hero at the top (video for morning, static illustration
/// for other times), then card stack with 22pt gap and 18pt horizontal padding,
/// closing on an `— end of today —` signoff.
/// Reads all records from DashboardViewModel (single-fetch architecture).
struct TodayTab: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var viewModel = HomeViewModel()
    @State private var searchText = ""
    // Default to `true` so cards are visible from the first render. The
    // previous default of `false` + a `.onAppear` flip was unreliable —
    // SwiftUI's AttributeGraph could finish a render pass before .onAppear
    // fired, leaving every card at .opacity(0) indefinitely (the "Today
    // tab blank below header" bug). Staggered fade-in is nice-to-have;
    // cards being visible is non-negotiable.
    @State private var cardsAppeared = true
    @State private var ambience = AmbienceManager.shared

    let onOpenProfile: () -> Void

    private let freshnessTracker = DataFreshnessTracker.shared

    init(onOpenProfile: @escaping () -> Void = {}) {
        self.onOpenProfile = onOpenProfile
    }

    var body: some View {
        let records = dashboardViewModel.allRecords
        let deliveries = dashboardViewModel.trackedDeliveries

        ScrollView {
            VStack(spacing: 0) {
                // 1. FULL-BLEED hero — lives outside the padded column.
                TodayHero(
                    timeOfDay: timeOfDay,
                    greeting: greetingText,
                    dateString: fullDateString,
                    onProfileTap: onOpenProfile,
                    isShowingCached: dashboardViewModel.isShowingCachedData
                )

                // 2. Padded feed column.
                LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.cardStack) {
                    // Search bar — sits directly under the hero with 14pt top padding.
                    TodaySearchBar(text: $searchText)
                        .padding(.top, 14)

                    // Error banner (when present).
                    if let loadError = viewModel.loadError ?? dashboardViewModel.error?.errorDescription {
                        ErrorBanner(
                            message: loadError,
                            retryAction: { Task { await dashboardViewModel.loadDashboard(forceRefresh: true) } },
                            onDismiss: {
                                viewModel.loadError = nil
                                dashboardViewModel.clearError()
                            }
                        )
                    }

                    // 3. Content state routing.
                    if !searchText.isEmpty {
                        SearchView(searchText: $searchText, records: records, deliveries: deliveries)
                    } else if dashboardViewModel.isLoading && records.isEmpty {
                        SkeletonCardsSection(count: 3)
                    } else if records.isEmpty && deliveries.isEmpty {
                        EmptyStateView(
                            icon: "tray",
                            title: "No data yet",
                            subtitle: "Pull to refresh or tap below to try syncing again.",
                            actionTitle: "Refresh"
                        ) {
                            Task { await dashboardViewModel.loadDashboard(forceRefresh: true) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        // Travel card (contextual — only when trip upcoming/active)
                        TravelHomeCard(records: records, deliveries: deliveries)

                        // Modular cards in time-of-day order
                        let orderedCards = HomeCardOrdering.orderedCards()
                        let isCompactHealth = HomeCardOrdering.isHealthCompact()
                        ForEach(Array(orderedCards.enumerated()), id: \.element) { index, cardType in
                            homeCard(for: cardType, compactHealth: isCompactHealth, records: records, deliveries: deliveries)
                                .cardAppear(index: index, appeared: cardsAppeared)
                        }

                        // 4. Signoff — "— end of today —"
                        Text("— end of today —")
                            .font(PerchTheme.Font.signoff)
                            .foregroundColor(timeOfDay.pageForeground)
                            .tracking(0.4)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, PerchTheme.Spacing.screenHorizontal)

                // Bottom padding for tab bar.
                Color.clear.frame(height: PerchTheme.TabBar.shellContentInsetHeight)
            }
        }
        // Page background flows from the hero's palette — dusky rose at dusk,
        // peach at sunrise, plum at night, etc. Creates a continuous atmosphere
        // instead of the old hard edge between hero image and neutral linen.
        .background(timeOfDay.pageBackground.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .refreshable {
            PerchHaptics.medium()
            await dashboardViewModel.loadDashboard(forceRefresh: true)
            PerchHaptics.success()
        }
        .onChange(of: dashboardViewModel.allRecords) { _, _ in
            viewModel.updateRecords(dashboardViewModel.allRecords, trackedDeliveries: dashboardViewModel.trackedDeliveries)
        }
        .onChange(of: dashboardViewModel.trackedDeliveries) { _, _ in
            viewModel.updateRecords(dashboardViewModel.allRecords, trackedDeliveries: dashboardViewModel.trackedDeliveries)
        }
        .onAppear {
            viewModel.updateRecords(dashboardViewModel.allRecords, trackedDeliveries: dashboardViewModel.trackedDeliveries)
        }
    }


    // MARK: - Modular Card Builder

    @ViewBuilder
    private func homeCard(for cardType: HomeCardType, compactHealth: Bool, records: [Record], deliveries: [DeliveryData]) -> some View {
        switch cardType {
        case .healthSummary:
            HealthSummaryHomeCard(records: records, compact: compactHealth)
        case .calendarToday:
            CalendarTodayCard(records: records)
        case .calendarTomorrow:
            CalendarTomorrowCard(records: records)
        case .nutrition:
            NutritionHomeCard(records: records)
        case .deliveries:
            DeliveryHomeCard(deliveries: deliveries)
        case .medications:
            MedicationsCard(records: records)
        case .weather:
            WeatherCompactCard(records: records)
        case .emailSummary:
            EmailSummaryCard(records: records)
        }
    }

    private var timeOfDay: TimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date.now)
        switch hour {
        case 5..<12:  return .sunrise
        case 12..<17: return .midday
        case 17..<22: return .dusk
        default:      return .night
        }
    }

    /// Time-of-day-specific greeting for the full-bleed header.
    /// Per Claude Design handoff: warm, British, never exclamatory.
    private var greetingText: String {
        switch timeOfDay {
        case .sunrise: return "Good morning,\nFabio."
        case .midday:  return "Afternoon,\nFabio."
        case .dusk:    return "Evening,\nFabio."
        case .night:   return "Still up,\nFabio?"
        }
    }

    /// "TUESDAY, 7 APRIL" — uppercase long-form date for the header date line.
    private var fullDateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: Date.now).uppercased()
    }

}

// MARK: - Time-of-day

enum TimeOfDay {
    case sunrise, midday, dusk, night

    var heroImage: String {
        switch self {
        case .sunrise: return "hero-morning"
        case .midday:  return "hero-afternoon"
        case .dusk:    return "hero-evening"
        case .night:   return "hero-night"
        }
    }

    /// Asset-catalog dataset name for the looping hero video. Only the
    /// morning video is currently treated as canonical per the handoff,
    /// but all four datasets are available in the bundle.
    var heroVideo: String? {
        switch self {
        case .sunrise: return "hero-morning-video"
        case .midday:  return "hero-afternoon-video"
        case .dusk:    return "hero-evening-video"
        case .night:   return "hero-night-video"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .sunrise: return "Sunrise scene"
        case .midday:  return "Midday scene"
        case .dusk:    return "Dusk scene"
        case .night:   return "Night scene"
        }
    }

    /// Page background tint — picks up the dominant warm tone of the hero
    /// image for each time of day so the hero flows seamlessly into the
    /// feed instead of hitting a hard edge against the neutral linen.
    /// Kept light enough that cream cards still read as elevated surfaces
    /// during day hours; goes to a dusky plum at night so cards glow.
    var pageBackground: Color {
        switch self {
        case .sunrise: return Color(red: 0.961, green: 0.878, blue: 0.780) // #F5E0C7 peach linen
        case .midday:  return Color(red: 0.929, green: 0.890, blue: 0.800) // #EDE3CC sage linen
        case .dusk:    return Color(red: 0.910, green: 0.820, blue: 0.816) // #E8D1D0 dusty rose
        case .night:   return Color(red: 0.176, green: 0.149, blue: 0.196) // #2D2632 deep plum
        }
    }

    /// Ink color that sits directly on pageBackground (signoff line,
    /// any page-level metadata). Auto-switches to cream at night so
    /// it's legible on the dark plum.
    var pageForeground: Color {
        switch self {
        case .night: return Color(red: 0.945, green: 0.918, blue: 0.867) // warm cream
        default:     return Color(red: 0.651, green: 0.608, blue: 0.545) // stone muted (textTertiary)
        }
    }

    /// When true, cards should lean into a slightly darker warm surface
    /// so text stays high-contrast against the dusky page.
    var prefersDarkSurfaces: Bool {
        switch self {
        case .night: return true
        default:     return false
        }
    }
}

// MARK: - Full-bleed Today hero (video or still + overlaid greeting)

/// Linen-variant header. Lives outside the padded feed column so it can
/// extend edge-to-edge. Loops a muted video when available (falls back to
/// the matching still), overlays two gradient scrims for legibility, and
/// floats greeting + date + profile avatar on top.
struct TodayHero: View {
    let timeOfDay: TimeOfDay
    let greeting: String
    let dateString: String
    let onProfileTap: () -> Void
    let isShowingCached: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Layer 1 — moving or still art. Clipped to header aspect.
            heroBackground
                .aspectRatio(1.0 / 0.82, contentMode: .fill)
                .clipped()

            // Layer 2 — bottom scrim (for greeting legibility)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0.0),
                    .init(color: .black.opacity(0), location: 0.40),
                    .init(color: Color(red: 0.078, green: 0.047, blue: 0.024).opacity(0.35), location: 0.70),
                    .init(color: Color(red: 0.078, green: 0.047, blue: 0.024).opacity(0.68), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)

            // Layer 3 — left-side vignette (puts greeting on calm ink)
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.078, green: 0.047, blue: 0.024).opacity(0.45), location: 0.0),
                    .init(color: Color(red: 0.078, green: 0.047, blue: 0.024).opacity(0.15), location: 0.40),
                    .init(color: .clear, location: 0.70),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .allowsHitTesting(false)

            // Layer 4 — greeting block, bottom-left
            HStack(alignment: .bottom, spacing: 10) {
                PerchBird(size: 22, color: Color(red: 0.969, green: 0.941, blue: 0.867), accent: PerchTheme.accent)
                    .padding(.bottom, 10)

                VStack(alignment: .leading, spacing: 8) {
                    Text(greeting)
                        .font(PerchTheme.Font.greeting)
                        .foregroundColor(Color(red: 0.969, green: 0.941, blue: 0.867)) // #F7F0DD
                        .lineSpacing(-8) // match the 1.02 line-height of the spec
                        .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 2)
                        .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)

                    HStack(spacing: 8) {
                        Text(dateString)
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .tracking(1.4)
                            .foregroundColor(Color(red: 0.969, green: 0.941, blue: 0.867).opacity(0.78))
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                        if isShowingCached {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(Color(red: 0.969, green: 0.941, blue: 0.867).opacity(0.85))
                                .transition(.opacity)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 22)
            .padding(.trailing, 22)
            .padding(.bottom, 22)

            // Layer 5 — avatar, top-right (inside safe area)
            avatar
                .padding(.trailing, 18)
                .padding(.top, 54) // leaves room for status bar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(timeOfDay.accessibilityLabel)
    }

    @ViewBuilder
    private var heroBackground: some View {
        if !reduceMotion, let videoName = timeOfDay.heroVideo {
            // Looping muted video. Falls back to the still inside the
            // player view if the asset can't be loaded.
            PerchLoopingVideo(assetName: videoName, posterName: timeOfDay.heroImage)
        } else {
            // Reduced motion or missing video → still illustration.
            Image(timeOfDay.heroImage)
                .resizable()
                .scaledToFill()
        }
    }

    private var avatar: some View {
        Button(action: onProfileTap) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [PerchTheme.accent, PerchTheme.wellness],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Text("F")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.973, blue: 0.925))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color(red: 1.0, green: 0.973, blue: 0.925).opacity(0.85), lineWidth: 2)
                )
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open profile")
    }
}

// MARK: - Linen search bar

struct TodaySearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(PerchTheme.textSecondary)
            TextField("Search", text: $text)
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textPrimary)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(PerchTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(PerchTheme.cardInnerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

// MARK: - Perch bird mascot (SVG → SwiftUI Shape composition)
//
// Exact composition from the Claude Design handoff (primitives.jsx → PerchBird):
// two circles + beak triangle + tail triangle + two foot rects.
// `color` is the body/head/tail ink; `accent` is the beak.

struct PerchBird: View {
    var size: CGFloat = 20
    var color: Color = PerchTheme.textPrimary
    var accent: Color = PerchTheme.accent

    var body: some View {
        // SVG viewBox is 80×56. Size parameter maps to viewBox width,
        // display height = size × 0.72 to preserve the viewBox ratio.
        Canvas { ctx, canvasSize in
            let sx = canvasSize.width / 80
            let sy = canvasSize.height / 56
            // body
            ctx.fill(Path(ellipseIn: CGRect(x: (36 - 14) * sx, y: (30 - 14) * sy, width: 28 * sx, height: 28 * sy)), with: .color(color))
            // head
            ctx.fill(Path(ellipseIn: CGRect(x: (52 - 8) * sx, y: (22 - 8) * sy, width: 16 * sx, height: 16 * sy)), with: .color(color))
            // eye
            ctx.fill(Path(ellipseIn: CGRect(x: (54 - 1.2) * sx, y: (21 - 1.2) * sy, width: 2.4 * sx, height: 2.4 * sy)), with: .color(Color(red: 0.969, green: 0.953, blue: 0.925)))
            // beak
            var beak = Path()
            beak.move(to: CGPoint(x: 58 * sx, y: 22 * sy))
            beak.addLine(to: CGPoint(x: 66 * sx, y: 20 * sy))
            beak.addLine(to: CGPoint(x: 60 * sx, y: 26 * sy))
            beak.closeSubpath()
            ctx.fill(beak, with: .color(accent))
            // tail
            var tail = Path()
            tail.move(to: CGPoint(x: 20 * sx, y: 34 * sy))
            tail.addLine(to: CGPoint(x: 12 * sx, y: 38 * sy))
            tail.addLine(to: CGPoint(x: 22 * sx, y: 38 * sy))
            tail.closeSubpath()
            ctx.fill(tail, with: .color(color))
            // feet (2 thin rects)
            ctx.fill(Path(CGRect(x: 38 * sx, y: 42 * sy, width: 1.4 * sx, height: 6 * sy)), with: .color(color))
            ctx.fill(Path(CGRect(x: 34 * sx, y: 42 * sy, width: 1.4 * sx, height: 6 * sy)), with: .color(color))
        }
        .frame(width: size, height: size * 0.72)
        .accessibilityHidden(true)
    }
}

// MARK: - Looping muted video (from asset-catalog data set)

/// Bundles and plays an MP4 stored as a Data Set asset. Writes the bytes
/// to a cached temp URL once, then loops through AVQueuePlayer + AVPlayerLooper.
/// Falls back to the poster image if the asset is missing or fails to load.
struct PerchLoopingVideo: UIViewRepresentable {
    let assetName: String
    let posterName: String

    func makeUIView(context: Context) -> PerchLoopingVideoView {
        PerchLoopingVideoView(assetName: assetName, posterName: posterName)
    }

    func updateUIView(_ uiView: PerchLoopingVideoView, context: Context) {}
}

final class PerchLoopingVideoView: UIView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private let playerLayer = AVPlayerLayer()
    private let fallbackImageView = UIImageView()

    init(assetName: String, posterName: String) {
        super.init(frame: .zero)
        backgroundColor = UIColor(red: 0.102, green: 0.078, blue: 0.039, alpha: 1)

        // Fallback image layer (always there as safety)
        fallbackImageView.image = UIImage(named: posterName)
        fallbackImageView.contentMode = .scaleAspectFill
        fallbackImageView.frame = bounds
        fallbackImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(fallbackImageView)

        // Configure player layer
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)

        // Load video data from asset catalog
        if let dataAsset = NSDataAsset(name: assetName) {
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(assetName).mp4")
            if !FileManager.default.fileExists(atPath: tmpURL.path) {
                try? dataAsset.data.write(to: tmpURL)
            }
            let item = AVPlayerItem(url: tmpURL)
            let queue = AVQueuePlayer()
            queue.isMuted = true
            looper = AVPlayerLooper(player: queue, templateItem: item)
            playerLayer.player = queue
            player = queue
            queue.play()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

// MARK: - Today card primitives (shared eyebrow + phrase + card wrapper)

/// Linen-variant card wrapper. Chrome-free: card surface color against the
/// page, 20pt radius, 20pt padding, no border, no shadow.
struct TodayCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)
                    .fill(PerchTheme.cardBackground)
            )
    }
}

/// Eyebrow row: [dot] LABEL · UPPERCASE · TRACKED      [freshness]
/// Dot is 6×6, colored by accent (wellness/kinetic). Label is 10.5pt
/// semibold, uppercase, 1.2 tracking, textSecondary. Freshness is mono,
/// 10.5pt, same color at 0.55 opacity.
struct TodayEyebrow: View {
    let label: String
    let accent: Color
    var freshness: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
            Text(label)
                .font(PerchTheme.Font.cardEyebrow)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundColor(PerchTheme.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let freshness {
                Text(freshness)
                    .font(PerchTheme.Font.freshness)
                    .tracking(0.3)
                    .foregroundColor(PerchTheme.textSecondary.opacity(0.55))
            }
        }
        .padding(.bottom, 8)
    }
}

/// Interpretive phrase row — the Gentler voice.
/// Fraunces-style italic serif (via .serif design fallback) at 20pt,
/// primary ink color, 1.3 line-height, small negative tracking.
/// Every phrase ends with a period (".") per the voice spec.
struct TodayPhrase: View {
    let text: String

    var body: some View {
        Text(text.hasSuffix(".") ? text : "\(text).")
            .font(PerchTheme.Font.phrase)
            .foregroundColor(PerchTheme.textPrimary)
            .lineSpacing(4)
            .tracking(-0.2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 16)
    }
}

/// Status chip used across cards (Now / in 2h / done / ETA).
/// Half-pill at 22pt tall with 11pt radius.
struct TodayChip: View {
    let text: String
    let color: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.1)
            .foregroundColor(color)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(
                Capsule(style: .continuous).fill(background)
            )
    }
}

// MARK: - Preview

#Preview {
    TodayTab()
        .environment(AuthViewModel())
        .environment(DashboardViewModel())
}
