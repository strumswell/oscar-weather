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
    @State private var expanded = true

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
        }
        .foregroundStyle(.white)
        .tint(.white)
        .padding(12)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
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
}
