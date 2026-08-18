import SwiftUI

/// The hourly detail sheet. The atmosphere sim fills the whole sheet and
/// renders the scrubbed hour; date and clock sit in the sheet's top bar, a
/// centered Now-style hero (big temperature, condition, day range) floats in
/// the sky, and the strip and minimap scroll the timeline under a
/// center-pinned playhead. Cards pick up the scene's hue via the Now stack's
/// card wash.
struct HourlyDetailView: View {
    var initialTarget: Date? = nil

    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location
    @Environment(\.dismiss) private var dismiss

    @State private var model = HourlyTimelineModel()
    @State private var dismissalFeedback = false
    @State private var dragStartTime: Double?

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
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if model.hasData {
                        HourlyDetailHeader(model: model)
                    }
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close, action: finish)
                }
            }
            .sensoryFeedback(.success, trigger: dismissalFeedback)
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
                // The 76pt line box carries a lot of top leading; the negative
                // padding tucks the digits up under the bar clock.
                HourlyDetailHero(model: model)
                    .padding(.top, -10)

                Spacer(minLength: 40)

                HourlyTimelineStrip(model: model)
                    .frame(height: 275)
                    .padding(.horizontal, 16)

                HourlyTimelineMinimap(model: model)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                HourlyLensRow(model: model)
                    .padding(.top, 12)
            }
            .padding(.bottom, 10)
        }
        .environment(\.cardTint, AtmosphereSampler.cardFill(snapshot: snapshot))
        .environment(\.cardBorderOpacity, AtmosphereSampler.cardBorderOpacity(snapshot: snapshot))
        // Full-strength material, unlike the Now stack's lighter frost: the
        // strip's hairlines and 10 pt labels need a steadier ground over the
        // animated sim.
        .environment(\.cardBackgroundStyle, AnyShapeStyle(.ultraThinMaterial))
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

    private func finish() {
        dismissalFeedback.toggle()
        dismiss()
    }
}

/// The sheet's title, living in the top bar: a small-caps date eyebrow over
/// the scrubbed clock time — this sheet's "place name" is a point in time.
/// Bare white + shadow, no glass behind it.
private struct HourlyDetailHeader: View {
    let model: HourlyTimelineModel

    var body: some View {
        VStack(spacing: 1) {
            Text(verbatim: model.dateLabel)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.72))
                .shadow(radius: 3)

            Text(verbatim: model.clockLabel)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .shadow(radius: 5)
        }
        .accessibilityHidden(true)
    }
}

/// The Now-style hero floating in the sky: big temperature, condition, and
/// the day's range — white + shadows, no card. Hit testing is off so sky
/// drags scrub right through the numbers.
private struct HourlyDetailHero: View {
    let model: HourlyTimelineModel

    @ScaledMetric(relativeTo: .largeTitle) private var temperatureFontSize: CGFloat = 76

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: model.temperatureLabel)
                .font(.system(size: temperatureFontSize))
                .foregroundStyle(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .shadow(radius: 12)

            Text(verbatim: model.conditionLabel)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(radius: 3)

            if let range = model.dayRangeLabel {
                Text(verbatim: range)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
                    .shadow(radius: 3)
            }
        }
        .padding(.horizontal, 20)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One shared timeline, swappable focus: the lens pills swap what the strip
/// shows without ever moving the playhead or the window.
private struct HourlyLensRow: View {
    let model: HourlyTimelineModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(HourlyLens.allCases) { lens in
                        pill(lens)
                            .id(lens.id)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.lens) { _, lens in
                withAnimation(.snappy) {
                    proxy.scrollTo(lens.id, anchor: .center)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: model.lens)
    }

    private func pill(_ lens: HourlyLens) -> some View {
        let isActive = model.lens == lens
        return Button {
            model.lens = lens
        } label: {
            Label(lens.title, systemImage: lens.systemImage)
                .font(.footnote.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.white.opacity(isActive ? 1 : 0.65))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .cardBackground(in: .capsule)
                .overlay {
                    Capsule().stroke(
                        .white.opacity(isActive ? 0.5 : 0.1),
                        lineWidth: 1
                    )
                }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HourlyDetailView()
        .environment(Weather.mock)
        .environment(Location())
        .environment(NowPresentationCoordinator())
}
