import SwiftUI

/// The hourly detail sheet. The atmosphere sim fills the whole sheet and
/// renders the scrubbed hour; the readout floats at the top (label color +
/// shadows over the sim), the strip and minimap scroll the timeline under a
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
            .navigationTitle("Stündlich")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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

            VStack(spacing: 12) {
                HourlyDetailHUD(model: model)

                HourlyReadoutRow(model: model)

                Spacer(minLength: 0)

                HourlyTimelineStrip(model: model)
                    .frame(height: 275)
                    .padding(.horizontal, 16)

                HourlyTimelineMinimap(model: model)
                    .padding(.horizontal, 16)

                HourlyLensRow(model: model)
            }
            .padding(.top, 2)
            .padding(.bottom, 10)
        }
        .environment(\.cardTint, AtmosphereSampler.cardFill(snapshot: snapshot))
        .environment(\.cardBorderOpacity, AtmosphereSampler.cardBorderOpacity(snapshot: snapshot))
        // Same lighter frost as the Now stack, so the cards match its look.
        .environment(\.cardBackgroundStyle, AnyShapeStyle(.ultraThinMaterial.opacity(0.6)))
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

/// The readout over the sim — Now-header treatment (white + shadows, no card):
/// time, temperature, and condition, plus a "Jetzt" return button once the
/// scrub has wandered off.
private struct HourlyDetailHUD: View {
    let model: HourlyTimelineModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: model.temperatureLabel)
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .shadow(radius: 8)
                Text(verbatim: model.conditionLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 3)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: model.clockLabel)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .monospacedDigit()
                    .shadow(radius: 3)
                Text(verbatim: model.dateLabel)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .monospacedDigit()
                    .shadow(radius: 3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .accessibilityHidden(true)
    }
}

/// Every series of the active lens as a bare readout row over the sim — the
/// same white-plus-shadow treatment as the header, no container chrome.
private struct HourlyReadoutRow: View {
    let model: HourlyTimelineModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(model.hudStats) { stat in
                    cell(stat)
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .shadow(radius: 3)
        .accessibilityHidden(true)
    }

    private func cell(_ stat: HourlyTimelineModel.HUDStat) -> some View {
        HStack(spacing: 6) {
            HourlySeriesSwatch(color: stat.color, kind: stat.swatch)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: stat.label)
                    .font(.system(size: 10, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.65))
                HStack(spacing: 3) {
                    if let degrees = stat.arrowDegrees {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 9))
                            .rotationEffect(.degrees(degrees))
                            .foregroundStyle(.teal)
                    }
                    Text(verbatim: stat.value)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
        }
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
                .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .cardBackground(in: .capsule)
                .overlay {
                    Capsule().stroke(
                        isActive ? Color.primary.opacity(0.35) : Color.white.opacity(0.08),
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
