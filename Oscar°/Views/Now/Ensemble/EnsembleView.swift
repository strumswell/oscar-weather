import SwiftUI

/// The ensemble page, built like the hourly sheet: the sky shows the weather
/// most runs agree on, the caption how sure that is, the deck where runs land.
struct EnsembleView: View {
    let initialDate: Date

    @Environment(Location.self) private var location
    @State private var state = EnsembleState()
    @State private var expandedLens: EnsembleLens? = .high

    var body: some View {
        EnsembleContent(state: state, expandedLens: $expandedLens)
            .navigationTitle("Ensemble")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    modelPicker
                }
            }
            .task(id: state.model) {
                await state.load(at: location.coordinates, anchor: initialDate)
            }
            .accessibilityIdentifier("ensemble.detail")
    }

    /// Toggles, not a Picker: menu toggles keep the provider headers and show
    /// the coverage as a subtitle instead of wrapping it into the name.
    private var modelPicker: some View {
        Menu {
            ForEach(DailyEnsembleModel.modelsByProvider, id: \.provider) { group in
                Section(group.provider.rawValue) {
                    ForEach(group.models) { model in
                        Toggle(isOn: Binding(get: { state.model == model }, set: { _ in state.model = model })) {
                            Text(verbatim: model.displayName)
                            Text(model.menuSubtitle)
                        }
                    }
                }
            }
        } label: {
            Text(verbatim: state.model.displayName)
        }
        .accessibilityLabel(Text("Wettermodell"))
        .accessibilityValue(Text(verbatim: state.model.displayName))
    }
}

/// The sim and everything over it; its own view so picking a day doesn't
/// rebuild the navigation bar.
private struct EnsembleContent: View {
    let state: EnsembleState
    @Binding var expandedLens: EnsembleLens?

    @Environment(Location.self) private var location

    var body: some View {
        let snapshot = state.selectedDay.map {
            AtmosphereWeatherMapper.snapshot(for: $0, at: location.coordinates, utcOffsetSeconds: state.utcOffsetSeconds)
        } ?? .twilight

        ZStack {
            WeatherSimulationView(snapshotOverride: snapshot)
                .ignoresSafeArea()

            if state.days.isEmpty {
                if state.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    ContentUnavailableView(
                        "Keine Ensemble-Daten",
                        systemImage: "chart.line.downtrend.xyaxis",
                        description: Text("Außerhalb der Modellabdeckung")
                    )
                }
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    DetailDeckCaption(eyebrow: state.eyebrowLabel, title: state.titleLabel, footnote: state.footnote)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 14)

                    EnsembleDeck(state: state, expandedLens: $expandedLens)
                        .padding(.horizontal, 16)

                    EnsembleRail(state: state)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }
                .padding(.bottom, 10)
            }
        }
        .animation(.smooth(duration: 0.3), value: snapshot)
        .sensoryFeedback(.selection, trigger: state.selectedIndex)
        .environment(\.cardTint, AtmosphereSampler.cardFill(snapshot: snapshot))
        .environment(\.cardBorderOpacity, AtmosphereSampler.cardBorderOpacity(snapshot: snapshot))
        .environment(\.cardBackgroundStyle, AnyShapeStyle(.ultraThinMaterial.opacity(0.6)))
    }
}

/// Every lens as a row with the selected day's value; the expanded row
/// carries its chart across all days.
private struct EnsembleDeck: View {
    let state: EnsembleState
    @Binding var expandedLens: EnsembleLens?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(EnsembleLens.allCases.enumerated(), id: \.element) { index, lens in
                let isExpanded = lens == expandedLens
                DetailDeckRow(
                    title: lens.title,
                    systemImage: lens.systemImage,
                    tint: lens.color,
                    value: state.rowValue(for: lens),
                    isExpanded: isExpanded,
                    showsDivider: index > 0 && !isExpanded && EnsembleLens.allCases[index - 1] != expandedLens,
                    toggle: {
                        withAnimation(.snappy) {
                            expandedLens = isExpanded ? nil : lens
                        }
                    }
                ) {
                    EnsembleChart(state: state, lens: lens)
                }
            }
        }
        .detailDeckCard()
    }
}
