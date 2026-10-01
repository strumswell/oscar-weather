import SwiftUI

/// The hourly detail sheet, organized as a deck: the atmosphere sim fills the
/// sheet and renders the scrubbed hour, and one card holds every lens as a
/// row showing its live value at that hour. The selected row expands in place
/// to carry the full chart, so scrubbing anywhere updates all rows at once.
/// The 14-day rail sits at the very bottom, in the thumb zone. Cards pick up
/// the scene's hue via the Now stack's card wash.
struct HourlyDetailView: View {
    var initialTarget: Date? = nil

    @Environment(Weather.self) private var weather: Weather
    @Environment(\.dismiss) private var dismiss

    @State private var model = HourlyTimelineModel()
    @State private var ensembleDate: Date?

    var body: some View {
        NavigationStack {
            Group {
                if model.hasData {
                    HourlyContent(model: model, isCovered: ensembleDate != nil)
                } else {
                    ContentUnavailableView(
                        "Keine stündlichen Daten",
                        systemImage: "clock.badge.questionmark",
                        description: Text("Für diesen Standort liegen aktuell keine stündlichen Details vor.")
                    )
                }
            }
            .navigationTitle("Stündlich")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Ensemble") {
                        ensembleDate = Date(timeIntervalSince1970: model.scrubTime)
                    }
                    .accessibilityHint(Text("Zeigt, wie sicher die Vorhersage der nächsten Wochen ist"))
                    .accessibilityIdentifier("hourly.ensemble")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close, action: finish)
                }
            }
            .navigationDestination(item: $ensembleDate) { date in
                EnsembleView(initialDate: date)
            }
            .onAppear {
                model.update(from: weather)
                if let initialTarget {
                    model.scrub(to: initialTarget.timeIntervalSince1970)
                }
            }
            .onChange(of: weather.lastUpdated) { _, _ in
                model.update(from: weather)
            }
        }
        // Sheets don't inherit the app root's forced scheme, but the whole
        // design (white ink, frost + wash over the sim) assumes dark.
        .preferredColorScheme(.dark)
    }

    private func finish() {
        dismiss()
    }
}

/// Reads the stage clock in its own body: re-evaluating the sheet's toolbar at
/// 10 Hz made the glass buttons re-layout mid-scrub.
private struct HourlyContent: View {
    let model: HourlyTimelineModel
    let isCovered: Bool

    @State private var expandedLens: HourlyLens? = .overview

    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location

    /// Stage pushes land ~10 Hz in 2-minute steps; this spring carries the
    /// sim and the card wash between them. Retargeted every push, it also
    /// low-passes fast scrubs across days into one continuous sweep instead
    /// of a strobe. Knob: shorter tracks tighter, longer smooths more.
    private static let stageTween: Animation = .smooth(duration: 0.3)

    var body: some View {
        let snapshot = AtmosphereWeatherMapper.snapshot(
            from: weather,
            at: location.coordinates,
            for: model.stageDate
        )
        // Only the stage clock is read here: everything that follows the raw
        // scrub time lives in child views, so the mapper above runs at the
        // stage's 10 Hz instead of every drag frame.
        ZStack {
            HourlyStage(model: model, snapshot: snapshot, isCovered: isCovered)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                HourlyCaption(model: model)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)

                HourlyDeck(model: model, expandedLens: $expandedLens)
                    .padding(.horizontal, 16)

                HourlyTimelineMinimap(model: model)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
            .padding(.bottom, 10)
        }
        .accessibilityIdentifier("hourly.detail")
        .animation(Self.stageTween, value: snapshot)
        .environment(\.cardTint, AtmosphereSampler.cardFill(snapshot: snapshot))
        .environment(\.cardBorderOpacity, AtmosphereSampler.cardBorderOpacity(snapshot: snapshot))
        .environment(\.cardBackgroundStyle, AnyShapeStyle(.ultraThinMaterial.opacity(0.6)))
    }
}

/// The sim with the sky drag and its VoiceOver readout. Reads the raw scrub
/// time (for the readout) in its own body, so those per-frame updates stop here.
private struct HourlyStage: View {
    let model: HourlyTimelineModel
    let snapshot: AtmosphereSnapshot
    let isCovered: Bool

    @State private var dragStartTime: Double?

    private static let secondsPerPoint: Double = 240

    var body: some View {
        WeatherSimulationView(isOffTab: isCovered, snapshotOverride: snapshot)
            .ignoresSafeArea()
            .contentShape(.rect)
            .gesture(skyDrag)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Himmel"))
            .accessibilityValue(Text(verbatim: model.accessibilityValue))
            .accessibilityAdjustableAction { direction in
                model.nudge(hours: direction == .increment ? 1 : -1)
            }
    }

    private var skyDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if dragStartTime == nil {
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragStartTime = model.scrubTime
                }
                guard let dragStartTime else { return }
                model.scrub(to: dragStartTime - value.translation.width * Self.secondsPerPoint)
            }
            .onEnded { _ in
                dragStartTime = nil
            }
    }
}

/// Eyebrow + title for the scrubbed hour; a child so its per-frame label
/// reads don't re-evaluate the sheet.
private struct HourlyCaption: View {
    let model: HourlyTimelineModel

    var body: some View {
        DetailDeckCaption(eyebrow: model.eyebrowLabel, title: model.titleLabel)
    }
}

/// The deck card: every lens as a row with its live value at the scrubbed
/// hour; the expanded row carries the chart in place. One gesture anywhere,
/// eight answers.
private struct HourlyDeck: View {
    let model: HourlyTimelineModel
    @Binding var expandedLens: HourlyLens?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(HourlyLens.allCases.enumerated(), id: \.element) { index, lens in
                let isExpanded = lens == expandedLens
                DetailDeckRow(
                    title: lens.title,
                    systemImage: lens.systemImage,
                    tint: model.layout(for: lens).primaryColor,
                    value: model.rowValue(for: lens) ?? "--",
                    isExpanded: isExpanded,
                    showsDivider: index > 0 && !isExpanded && HourlyLens.allCases[index - 1] != expandedLens,
                    toggle: {
                        withAnimation(.snappy) {
                            expandedLens = isExpanded ? nil : lens
                        }
                    }
                ) {
                    HourlyTimelineStrip(model: model, lens: lens)
                }
            }
        }
        .detailDeckCard()
    }
}

#Preview {
    HourlyDetailView()
        .environment(Weather.mock)
        .environment(Location())
        .environment(NowPresentationCoordinator())
}
