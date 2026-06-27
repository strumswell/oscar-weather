//
//  AtmosphereDebugPanel.swift
//  Oscar°
//
//  Floating control panel shown in debug mode (10 taps on the head view).
//  Drives AtmosphereDebugState so the weather simulation can be scrubbed
//  through times of day, conditions, and intensities while tweaking visuals.
//

import SwiftUI

struct AtmosphereDebugPanel: View {
    @Bindable var state: AtmosphereDebugState
    @Environment(Location.self) private var location
    @State private var expanded = true
    @State private var moonReferenceDate = Date.now
    @State private var moonRise: Date?
    @State private var moonSet: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(isOn: $state.overrideEnabled) {
                    Text("Override")
                        .font(.caption.bold())
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expanded.toggle()
                    }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.caption.bold())
                        .padding(6)
                        .contentShape(Rectangle())
                }
            }

            if expanded, state.overrideEnabled {
                HStack {
                    Text("Condition")
                        .frame(width: 64, alignment: .leading)
                    Picker("Condition", selection: $state.condition) {
                        ForEach(AtmosphereConditionFamily.debugCases, id: \.self) { condition in
                            Text(condition.debugLabel).tag(condition)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                    Spacer()
                }
                .font(.caption2.monospaced())

                sliderRow("Time", value: $state.timeOfDay, label: timeLabel)
                sliderRow("Intensity", value: $state.intensity, label: percentLabel(state.intensity))
                sliderRow("Clouds", value: $state.cloudCoverage, label: percentLabel(state.cloudCoverage))
                sliderRow("Wind", value: $state.windSpeed, label: percentLabel(state.windSpeed))
                sliderRow("Wind Dir", value: $state.windDirectionDegrees, in: 0...360, label: "\(Int(state.windDirectionDegrees))°")
                sliderRow("Haze/AQI", value: $state.aqiHaze, label: percentLabel(state.aqiHaze))
                sliderRow("Moon", value: $state.moonPhase, label: moonLabel)
            }

            if expanded {
                moonInfoSection
            }
        }
        .foregroundStyle(.white)
        .tint(.white)
        .padding(12)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .task { recomputeMoon() }
    }

    /// Current (real, not overridden) moon phase plus the next moonrise/moonset for the
    /// active location — handy for sanity-checking the rendered moon against an almanac.
    private var moonInfoSection: some View {
        let phase = MoonPhase.phaseFraction(for: moonReferenceDate)
        return VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
            infoRow("Moon", "\(MoonPhase.name(for: phase)) · \(percentLabel(MoonPhase.illumination(for: phase))) · φ\(String(format: "%.2f", phase))")
            infoRow("Rise", moonRise.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
            infoRow("Set", moonSet.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption2.monospaced())
    }

    private func recomputeMoon() {
        let now = Date.now
        moonReferenceDate = now
        let (rise, set) = MoonPhase.riseAndSet(
            after: now,
            latitude: location.coordinates.latitude,
            longitude: location.coordinates.longitude
        )
        moonRise = rise
        moonSet = set
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0...1,
        label: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 64, alignment: .leading)
            Slider(value: value, in: range)
            Text(label)
                .frame(width: 44, alignment: .trailing)
        }
        .font(.caption2.monospaced())
    }

    private var timeLabel: String {
        let minutes = Int((state.timeOfDay * 24 * 60).rounded())
        return String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    private var moonLabel: String {
        percentLabel(MoonPhase.illumination(for: state.moonPhase))
    }

    private func percentLabel(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

#Preview {
    ZStack {
        Color.blue
        AtmosphereDebugPanel(state: AtmosphereDebugState())
            .padding()
    }
    .environment(Location())
}
