import SwiftUI

/// Settings > Ansicht. A segment picks what to edit. Kennzahlen: the head
/// under the real sky and an edit list that sorts (drag handle) and shows
/// or hides (check circle) its rows; hidden rows keep their place in the
/// order, and the circles are buttons, not List selection, since a drag on
/// a selected row would carry every selected row along. Abschnitte: the
/// page itself as a drag canvas, see `NowLayoutCanvas`.
struct NowLayoutSettingsView: View {
    enum Part { case metrics, sections }

    /// Trailing under a back button (Settings push), leading beside the
    /// sheet's close button.
    var resetPlacement: ToolbarItemPlacement = .topBarTrailing

    @Environment(Weather.self) private var weather
    private let settingsService = SettingService.shared
    @State private var part: Part = .metrics

    private var isDefault: Bool {
        settingsService.arrangementsAreDefault
            && settingsService.headMetricOrder == HeadMetric.allCases
            && settingsService.hiddenHeadMetrics == HeadMetric.defaultHidden
    }

    private var metricsFull: Bool {
        settingsService.headMetrics.count >= HeadMetric.maxShown
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Bearbeiten", selection: $part) {
                Text("Kennzahlen").tag(Part.metrics)
                Text("Abschnitte").tag(Part.sections)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 4)

            switch part {
            case .metrics:
                NowLayoutPreview()
                    .padding(16)
                metricsList
            case .sections:
                NowLayoutCanvas()
                    .padding(.vertical, 16)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Ansicht")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: resetPlacement) {
                Button("Standard wiederherstellen", systemImage: "slider.horizontal.2.arrow.trianglehead.counterclockwise", action: restoreDefault)
                    .disabled(isDefault)
            }
        }
    }

    private var metricsList: some View {
        List {
            Section {
                ForEach(settingsService.headMetricOrder, id: \.self) { metric in
                    let isHidden = settingsService.hiddenHeadMetrics.contains(metric)
                    CheckRow(isOn: !isHidden) {
                        settingsService.hiddenHeadMetrics.formSymmetricDifference([metric])
                    } label: {
                        Label { Text(metric.title) } icon: { Image(systemName: metric.systemImage) }
                            .labelStyle(.settingsIcon(metric.tint))
                        Spacer()
                        Text(metric.value(in: weather) ?? "–")
                            .foregroundStyle(.secondary)
                    }
                    .disabled(metricsFull && isHidden)
                }
                .onMove { settingsService.headMetricOrder.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                HStack {
                    Text("Unter der Temperatur")
                    Spacer()
                    Text("\(settingsService.headMetrics.count) von \(HeadMetric.maxShown)")
                }
            }
        }
    }

    private func restoreDefault() {
        withAnimation(.snappy) {
            settingsService.resetArrangements()
            settingsService.headMetricOrderRaw = nil
            settingsService.hiddenHeadMetricsRaw = nil
        }
    }
}

/// A row with a leading check circle that looks like List's edit-mode
/// selection; the whole row toggles.
private struct CheckRow<Content: View>: View {
    let isOn: Bool
    let toggle: () -> Void
    @ViewBuilder let label: Content

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            withAnimation(.snappy, toggle)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary), .tint)
                    .contentTransition(.symbolEffect(.replace))
                label
            }
            .opacity(isEnabled ? 1 : 0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
