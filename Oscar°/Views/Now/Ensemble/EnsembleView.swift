import SwiftUI

struct EnsembleView: View {
    let initialDate: Date

    @Environment(Location.self) private var location
    @State private var state = EnsembleState()
    @State private var expandedLens: EnsembleLens? = .high

    var body: some View {
        EnsembleContent(state: state, expandedLens: $expandedLens)
            .navigationTitle("Ensemble")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: state.model) {
                await state.load(at: location.coordinates, anchor: initialDate)
            }
            .accessibilityIdentifier("ensemble.detail")
    }
}

private struct EnsembleModelPicker: View {
    let state: EnsembleState

    var body: some View {
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
            HStack(spacing: 4) {
                Text(verbatim: state.model.displayName)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .accessibilityLabel(Text("Wettermodell"))
        .accessibilityValue(Text(verbatim: state.model.displayName))
    }
}

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
                    ContentUnavailableView {
                        Label("Keine Ensemble-Daten", systemImage: "chart.line.downtrend.xyaxis")
                    } description: {
                        Text("Außerhalb der Modellabdeckung")
                    } actions: {
                        EnsembleModelPicker(state: state)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    ZStack(alignment: Alignment(horizontal: .trailing, vertical: .firstTextBaseline)) {
                        DetailDeckCaption(eyebrow: state.eyebrowLabel, title: state.titleLabel, footnote: state.footnote)
                        EnsembleModelPicker(state: state)
                    }
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
