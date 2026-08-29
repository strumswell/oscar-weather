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
    @Environment(Location.self) private var location: Location
    @Environment(\.dismiss) private var dismiss

    private let settingsService = SettingService.shared

    @State private var model = HourlyTimelineModel()
    @State private var expandedLens: HourlyLens? = .overview
    @State private var dismissalFeedback = false
    @State private var dragStartTime: Double?

    private var showsChapters: Bool { settingsService.hourlyDetailShowsChapters }

    private static let secondsPerPoint: Double = 240

    var body: some View {
        NavigationStack {
            Group {
                if model.hasData {
                    content
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
                    if model.hasData {
                        Button {
                            withAnimation(.snappy) {
                                settingsService.hourlyDetailShowsChapters.toggle()
                            }
                        } label: {
                            Image(systemName: showsChapters ? "list.bullet" : "calendar.day.timeline.left")
                        }
                        .accessibilityLabel(showsChapters ? Text("Alle Werte anzeigen") : Text("Verlauf anzeigen"))
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close, action: finish)
                }
            }
            .sensoryFeedback(.success, trigger: dismissalFeedback)
            .sensoryFeedback(.selection, trigger: expandedLens)
            .sensoryFeedback(.selection, trigger: showsChapters)
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

    private var content: some View {
        let snapshot = AtmosphereWeatherMapper.snapshot(
            from: weather,
            at: location.coordinates,
            for: model.stageDate
        )
        return ZStack {
            WeatherSimulationView(snapshotOverride: snapshot)
                .ignoresSafeArea()
                .contentShape(.rect)
                .gesture(skyDrag)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Himmel"))
                .accessibilityValue(Text(verbatim: model.accessibilityValue))
                .accessibilityAdjustableAction { direction in
                    model.nudge(hours: direction == .increment ? 1 : -1)
                }

            VStack(spacing: 0) {
                if showsChapters {
                    HourlyChaptersView(model: model)
                } else {
                    Spacer(minLength: 0)

                    captionRow
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)

                    HourlyDeck(model: model, expandedLens: $expandedLens)
                        .padding(.horizontal, 16)
                }

                HourlyTimelineMinimap(model: model)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
            .padding(.bottom, 10)
        }
        .environment(\.cardTint, AtmosphereSampler.cardFill(snapshot: snapshot))
        .environment(\.cardBorderOpacity, AtmosphereSampler.cardBorderOpacity(snapshot: snapshot))
        .environment(\.cardBackgroundStyle, AnyShapeStyle(.ultraThinMaterial.opacity(0.6)))
    }

    private var captionRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: model.eyebrowLabel)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.72))
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)

            Text(verbatim: model.titleLabel)
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 2.5, y: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Gestures

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

    private func finish() {
        dismissalFeedback.toggle()
        dismiss()
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
            ForEach(Array(HourlyLens.allCases.enumerated()), id: \.element) { index, lens in
                let isExpanded = lens == expandedLens
                // The expanded block separates itself with its own highlight;
                // hairlines only run between collapsed rows.
                if index > 0, !isExpanded, HourlyLens.allCases[index - 1] != expandedLens {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                        .frame(height: 1)
                }
                row(lens, isExpanded: isExpanded)
            }
        }
        .padding(6)
        .cardBackground(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .cardBorder(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// One view per lens in both states so the header keeps its identity
    /// across the toggle; the chart unfolds from under it, clipped.
    private func row(_ lens: HourlyLens, isExpanded: Bool) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    expandedLens = isExpanded ? nil : lens
                }
            } label: {
                rowHeader(lens, isExpanded: isExpanded)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                HourlyTimelineStrip(model: model, lens: lens)
                    .frame(height: 176)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(isExpanded ? 0.09 : 0))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func rowHeader(_ lens: HourlyLens, isExpanded: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: lens.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(model.layout(for: lens).primaryColor)
                .frame(width: 24)

            Text(lens.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: model.rowValue(for: lens) ?? "--")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))

            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(isExpanded ? 0.5 : 0.4))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lens.title)
        .accessibilityValue(Text(verbatim: model.rowValue(for: lens) ?? ""))
        .accessibilityHint(isExpanded ? Text("Klappt das Diagramm ein") : Text("Zeigt das Diagramm"))
    }
}

#Preview {
    HourlyDetailView()
        .environment(Weather.mock)
        .environment(Location())
        .environment(NowPresentationCoordinator())
}
