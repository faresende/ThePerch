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
        let timeOfDay = PerchTimeOfDay.current
        let palette = PerchPalette.forTimeOfDay(timeOfDay)

        ScrollView {
            VStack(spacing: 0) {
                // 1. FULL-BLEED hero — lives outside the padded column.
                TodayHero(
                    timeOfDay: timeOfDay,
                    greeting: timeOfDay.greeting,
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
                            .foregroundColor(palette.faint)
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
        // Page background = active palette's `bg` token. Because the V1
        // seam gradient in TodayHero fades into this same value at its
        // bottom edge, the whole page reads as a single continuous surface.
        .background(palette.bg.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .environment(\.perchPalette, palette)
        .environment(\.perchTimeOfDay, timeOfDay)
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

    /// "TUESDAY, 7 APRIL" — uppercase long-form date for the header date line.
    private var fullDateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: Date.now).uppercased()
    }

}

// MARK: - Full-bleed Today hero (video or still + overlaid greeting)

/// Full-bleed hero. 320pt tall, fixed height. V1 seam gradient fades the
/// illustration into the page bg so the hero dissolves into the feed with
/// no hard edge — palette-driven scrimDark (NOT pure black) + the active
/// palette's bg at the bottom of the stack. Greeting overlaid bottom-left,
/// avatar floats top-right.
struct TodayHero: View {
    let timeOfDay: PerchTimeOfDay
    let greeting: String
    let dateString: String
    let onProfileTap: () -> Void
    let isShowingCached: Bool

    @Environment(\.perchPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Layer 1 — looping video (morning) or static illustration.
            heroBackground
                .frame(height: 320)
                .frame(maxWidth: .infinity)
                .clipped()

            // Layer 2 — V1 seam gradient. Fades top→bottom from transparent
            // (untouched image) through scrimDark at 0.15 (for greeting
            // legibility) into the page bg (so the illustration dissolves
            // into the feed seamlessly). Per handoff, stops are fixed;
            // only scrimDark + bg change per palette.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: .clear, location: 0.35),
                    .init(color: palette.scrimDark.opacity(0.15), location: 0.55),
                    .init(color: palette.bg.opacity(0.35),        location: 0.72),
                    .init(color: palette.bg.opacity(0.75),        location: 0.88),
                    .init(color: palette.bg,                       location: 1.00),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)

            // Layer 3 — greeting block, bottom-left (22pt insets).
            HStack(alignment: .bottom, spacing: 10) {
                PerchBird(size: 22, color: palette.heroText, accent: palette.kinetic)
                    .padding(.bottom, 10)

                VStack(alignment: .leading, spacing: 10) {
                    Text(greeting)
                        .font(PerchTheme.Font.greeting)
                        .foregroundColor(palette.heroText)
                        .tracking(-0.5)
                        .lineSpacing(-8) // → effective 1.02 line-height at 34pt
                        .shadow(color: palette.scrimDark.opacity(0.6), radius: 10, x: 0, y: 2)
                        .shadow(color: palette.scrimDark.opacity(0.4), radius: 1, x: 0, y: 1)

                    HStack(spacing: 8) {
                        Text(dateString)
                            .font(.system(size: 11))
                            .tracking(1.4)
                            .foregroundColor(palette.heroText.opacity(0.78))
                            .shadow(color: palette.scrimDark.opacity(0.5), radius: 3, x: 0, y: 1)

                        if isShowingCached {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(palette.heroText.opacity(0.85))
                                .transition(.opacity)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 22)
            .padding(.trailing, 22)
            .padding(.bottom, 34)

            // Layer 4 — avatar, top-right.
            avatar
                .padding(.trailing, 20)
                .padding(.top, 54) // clears the status bar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(height: 320)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityLabel(timeOfDay.accessibilityLabel)
    }

    @ViewBuilder
    private var heroBackground: some View {
        if !reduceMotion, let videoName = timeOfDay.heroVideoName {
            PerchLoopingVideo(assetName: videoName, posterName: timeOfDay.heroImageName)
        } else {
            Image(timeOfDay.heroImageName)
                .resizable()
                .scaledToFill()
        }
    }

    private var avatar: some View {
        Button(action: onProfileTap) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [palette.kinetic, palette.wellness],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Text("F")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(palette.heroText)
                )
                .overlay(
                    Circle()
                        .strokeBorder(palette.heroText.opacity(0.85), lineWidth: 2)
                )
                .frame(width: 36, height: 36)
                .shadow(color: palette.scrimDark.opacity(0.45), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open profile")
    }
}

// MARK: - Search bar

struct TodaySearchBar: View {
    @Binding var text: String
    @Environment(\.perchPalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(palette.muted)
            TextField("Search", text: $text)
                .font(PerchTheme.Font.body)
                .foregroundColor(palette.ink)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(palette.faint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(palette.chipBg)
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
//
// All primitives read their colours from `@Environment(\.perchPalette)`
// so swapping the palette on TodayTab re-tints the entire feed atomically.

/// Card wrapper. Chrome-free: palette card surface, 20pt radius, 20pt
/// padding, no border, no shadow.
struct TodayCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content
    @Environment(\.perchPalette) private var palette

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)
                    .fill(palette.card)
            )
    }
}

/// Eyebrow row: [dot] LABEL · UPPERCASE · TRACKED      [freshness]
/// Dot = 6pt accent colour (caller chooses kinetic/wellness from palette).
/// Label = palette.muted. Freshness = palette.faint.
struct TodayEyebrow: View {
    let label: String
    /// Pass `palette.kinetic` or `palette.wellness` from the parent card.
    let accent: Color
    var freshness: String? = nil
    @Environment(\.perchPalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
            Text(label)
                .font(PerchTheme.Font.cardEyebrow)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundColor(palette.muted)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let freshness {
                Text(freshness)
                    .font(PerchTheme.Font.freshness)
                    .tracking(0.3)
                    .foregroundColor(palette.muted.opacity(0.55))
            }
        }
        .padding(.bottom, 10)
    }
}

/// Interpretive phrase row — Fraunces-style italic serif, 22pt
/// per the palette-change handoff. Colour = palette.ink.
struct TodayPhrase: View {
    let text: String
    @Environment(\.perchPalette) private var palette

    var body: some View {
        Text(text.hasSuffix(".") ? text : "\(text).")
            .font(PerchTheme.Font.phrase)
            .foregroundColor(palette.ink)
            .lineSpacing(4)
            .tracking(-0.3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 16)
    }
}

/// Status chip. Palette-aware but accepts overrides for the special
/// "Now" (white on wellness) / out-for-delivery (white on kinetic) cases.
struct TodayChip: View {
    let text: String
    let color: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.1)
            .foregroundColor(color)
            .padding(.horizontal, 10)
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
