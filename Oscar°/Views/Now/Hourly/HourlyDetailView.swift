import SwiftUI

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
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(role: .close, action: finish)
                        }
                    }
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
        .preferredColorScheme(.dark)
    }

    private func finish() {
        dismiss()
    }
}

private struct HourlyContent: View {
    let model: HourlyTimelineModel
    let isCovered: Bool

    @State private var expandedLens: HourlyLens? = .overview

    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location

    private static let stageTween: Animation = .smooth(duration: 0.3)

    var body: some View {
        let snapshot = AtmosphereWeatherMapper.snapshot(
            from: weather,
            at: location.coordinates,
            for: model.stageDate
        )
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

private struct HourlyCaption: View {
    let model: HourlyTimelineModel

    var body: some View {
        DetailDeckCaption(eyebrow: model.eyebrowLabel, title: model.titleLabel)
    }
}

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
