import SwiftUI

/// Settings > Ansicht. A segment picks what to edit, the band under it shows
/// that part under the real sky, and one edit list sorts (drag handle) and
/// shows or hides (check circle) its rows. Hidden rows keep their place in
/// the order. The circles are buttons, not List selection: a drag on a
/// selected row would carry every selected row along.
struct NowLayoutSettingsView: View {
    enum Part { case metrics, sections }

    @Environment(Weather.self) private var weather
    private let settingsService = SettingService.shared
    @State private var part: Part = .metrics

    private var isDefault: Bool {
        settingsService.nowSectionOrder == NowSection.allCases
            && settingsService.hiddenNowSections.isEmpty
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

            NowLayoutPreview(part: part)
                .padding(16)

            switch part {
            case .metrics: metricsList
            case .sections: sectionsList
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Ansicht")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Standard wiederherstellen", systemImage: "arrow.counterclockwise", action: restoreDefault)
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

    private var sectionsList: some View {
        List {
            Section {
                ForEach(settingsService.nowSectionOrder, id: \.self) { section in
                    CheckRow(isOn: !settingsService.hiddenNowSections.contains(section)) {
                        settingsService.hiddenNowSections.formSymmetricDifference([section])
                    } label: {
                        Label { Text(section.title) } icon: { Image(systemName: section.systemImage) }
                            .labelStyle(.settingsIcon(section.tint))
                    }
                }
                .onMove { settingsService.nowSectionOrder.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Wetterabschnitte")
            }
        }
    }

    private func restoreDefault() {
        Haptics.impact()
        withAnimation(.snappy) {
            settingsService.nowSectionOrderRaw = nil
            settingsService.hiddenNowSectionsRaw = nil
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
            Haptics.impact()
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
