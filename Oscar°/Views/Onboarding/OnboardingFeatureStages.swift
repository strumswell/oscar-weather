//
//  OnboardingFeatureStages.swift
//  Oscar°
//

import SwiftUI

/// Card fill for components shown with staged data over an animated sky
/// (onboarding, the layout preview in Settings). A translucent fill instead
/// of the cards' live material: plain alpha, no per-frame re-blur.
let stagedCardFill = AnyShapeStyle(Color(uiColor: .systemBackground).opacity(0.78))

/// The picture in the hero window of each feature page, built from the real
/// app views with staged data. Fills whatever height the hero window has;
/// the collage runs edge to edge, the rest sit inset.
struct OnboardingFeatureStage: View {
    let page: OnboardingFeaturePage
    var radarGrids: Task<[[UInt8]], Never>?

    var body: some View {
        Group {
            switch page {
            case .forecast: inset { ForecastStage() }
            case .radar: inset { OnboardingMapStage(prebuiltGrids: radarGrids) }
            case .ensemble: inset { EnsembleStage() }
            case .extras: OnboardingExtrasStage()
            }
        }
        .environment(\.cardBackgroundStyle, stagedCardFill)
    }

    /// Phone-wide, with air on the sides and a stop above the feather so
    /// the picture never runs into the dark part under it.
    private func inset(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(maxWidth: OnboardingStage.contentMaxWidth)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, OnboardingStage.featherHeight / 2)
    }
}

/// Hourly cards, the day list and the logos of the services behind them.
private struct ForecastStage: View {
    var body: some View {
        // Small phones drop the day list rather than squeeze everything.
        ViewThatFits(in: .vertical) {
            VStack(spacing: 12) {
                hourlyRow
                CollageDailyCard()
                logos
            }
            VStack(spacing: 12) {
                hourlyRow
                logos
            }
        }
        .accessibilityHidden(true)
    }

    private var hourlyRow: some View {
        ViewThatFits(in: .horizontal) {
            HourlyRow(count: 5)
            HourlyRow(count: 4)
            HourlyRow(count: 3)
        }
    }

    private var logos: some View {
        HStack(spacing: 22) {
            ProviderLogo(asset: "logo-dwd", height: 30)
            ProviderLogo(asset: "logo-ecmwf", height: 16)
            ProviderLogo(asset: "logo-noaa", height: 30)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 1)
        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
        .padding(.top, 4)
    }
}

private struct HourlyRow: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingSampleData.hourlyItems.prefix(count)) { item in
                HourlyForecastCard(item: item)
            }
        }
    }
}

/// The ensemble page's own caption, deck and day rail with sixteen staged
/// days. Live like the real page: drag the chart or tap a row.
private struct EnsembleStage: View {
    @State private var state = EnsembleState()
    @State private var expandedLens: EnsembleLens? = .high

    var body: some View {
        OnboardingAppPanel {
            // Shorter hero windows (small phones, the Duo's cover) drop rows,
            // then the caption.
            ViewThatFits(in: .vertical) {
                content(lenses: [.high, .precipitation, .sky], showsRail: true)
                content(lenses: [.high, .precipitation], showsRail: false)
                content(lenses: [.high], showsRail: false)
                content(lenses: [.high], showsRail: false, showsCaption: false)
            }
        }
        .onAppear {
            // Tomorrow: fairly sure, not a done deal.
            if state.days.isEmpty {
                state.stage(OnboardingSampleData.ensembleDays, selectedIndex: 1)
            }
        }
    }

    private func content(lenses: [EnsembleLens], showsRail: Bool, showsCaption: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsCaption {
                DetailDeckCaption(eyebrow: state.eyebrowLabel, title: state.titleLabel, footnote: state.footnote)
                    .padding(.horizontal, 6)
            }

            VStack(spacing: 0) {
                ForEach(lenses.enumerated(), id: \.element) { index, lens in
                    let isExpanded = lens == expandedLens
                    DetailDeckRow(
                        title: lens.title,
                        systemImage: lens.systemImage,
                        tint: lens.color,
                        value: state.rowValue(for: lens),
                        isExpanded: isExpanded,
                        showsDivider: index > 0 && !isExpanded && lenses[index - 1] != expandedLens,
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

            if showsRail {
                EnsembleRail(state: state)
            }
        }
    }
}

/// A rounded window into the app: the night-blue page the real cards are
/// designed for, so their white text reads the way it does in Oscar.
private struct OnboardingAppPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(OnboardingStage.navy, in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .environment(\.colorScheme, .dark)
    }
}

#Preview {
    TabView {
        ForEach(OnboardingFeaturePage.allCases, id: \.self) { page in
            OnboardingFeatureStage(page: page)
                .padding()
                .frame(height: 460)
        }
    }
    .tabViewStyle(.page)
    .background(.blue)
    .environment(Weather.mock)
}
