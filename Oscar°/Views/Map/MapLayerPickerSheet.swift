//
//  MapLayerPickerSheet.swift
//  Oscar°
//
//  Apple-Maps-style "Kartenebenen" sheet: layer tiles grouped by kind and
//  region, plus display toggles.
//

import SwiftUI
import UIKit

// MARK: - Layer picker sheet

/// Apple-Maps-style "Kartenmodi" sheet: square screenshot tiles per layer, grouped
/// by kind (live radar vs. model forecast) and region, plus display toggles.
/// Selection state reads straight from the observable SettingService, so tiles
/// re-ring live while the sheet stays open and the map swaps behind it.
struct MapLayerPickerSheet: View {
    @Bindable var settingsService: SettingService
    let onSelectRadar: (RadarRegion) -> Void
    let onSelectTileLayer: (WeatherTileLayer) -> Void
    @Environment(\.dismiss) private var dismissSheet
    @State private var showsModelInfo = false

    private static let tileColumns = Array(
        repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    radarSection
                    productSection(title: "Regen", layers: [.iconPrecip, .gfsPrecip])
                    productSection(title: "Temperatur", layers: [.iconTemp, .gfsTemp])
                    productSection(title: "Wind", layers: [.iconWind, .gfsWind])
                    displaySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .navigationTitle("Kartenebenen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // No text label: with a bare .close role the system renders
                    // the standard glass X and localizes the accessibility label.
                    Button(role: .close, action: { dismissSheet() })
                }
            }
            .containerBackground(.clear, for: .navigation)
            .navigationDestination(isPresented: $showsModelInfo) {
                WeatherModelInfoView()
            }
        }
        .task {
            // Testing hook: `-autoPresentModelInfo YES` jumps straight to the
            // weather-model explainer (screenshot flows without touch input).
            guard UserDefaults.standard.bool(forKey: "autoPresentModelInfo") else { return }
            showsModelInfo = true
        }
    }

    // MARK: Sections

    private var radarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LayerPickerSectionHeader(title: "Radar", detail: "Live + Kurzprognose",
                                     showsLiveDot: true)
            LazyVGrid(columns: Self.tileColumns, spacing: 14) {
                LayerTile(title: "Zentraleuropa", subtitle: "DWD",
                          imageName: "layer-radar-germany",
                          isSelected: isRadarSelected(.germany),
                          action: { select { onSelectRadar(.germany) } })
                LayerTile(title: "Europa", subtitle: "OPERA",
                          imageName: "layer-radar-europe",
                          isSelected: isRadarSelected(.europe),
                          action: { select { onSelectRadar(.europe) } })
                LayerTile(title: "USA", subtitle: "NOAA",
                          imageName: "layer-radar-usa",
                          isSelected: isRadarSelected(.usa),
                          action: { select { onSelectRadar(.usa) } })
            }
        }
    }

    private func productSection(title: LocalizedStringKey,
                                layers: [WeatherTileLayer]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LayerPickerSectionHeader(title: title, detail: nil,
                                     infoSymbol: "questionmark.circle",
                                     onInfoTap: { showsModelInfo = true })
            LazyVGrid(columns: Self.tileColumns, spacing: 14) {
                ForEach(layers, id: \.self) { layer in
                    LayerTile(title: layer.pickerRegion,
                              subtitle: LocalizedStringKey(layer.sourceLabel),
                              imageName: layer.previewImageName,
                              isSelected: settingsService.activeTileLayer == layer,
                              action: { select { onSelectTileLayer(layer) } })
                }
            }
        }
    }

    /// The typed radar product exists for DWD and MRMS coverage, not OPERA.
    private var precipTypeAvailable: Bool {
        !(settingsService.oscarRadarLayer && settingsService.oscarRadarRegion == .europe)
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LayerPickerSectionHeader(title: "Darstellung", detail: nil)
            VStack(spacing: 0) {
                LayerToggleRow(title: "Flüssige Bewegungen",
                               subtitle: "Sanfte Übergänge zwischen den Bildern",
                               isOn: $settingsService.radarSmoothMotion)
                Divider().padding(.leading, 16)
                LayerToggleRow(title: "Weichzeichnen",
                               subtitle: "Weiche Kanten statt harter Farbstufen",
                               isOn: $settingsService.radarSoftRendering)
                Divider().padding(.leading, 16)
                LayerToggleRow(title: "Bewegungspfeile",
                               subtitle: "Zugrichtung im Regenradar",
                               isOn: $settingsService.radarMotionArrows)
                Divider().padding(.leading, 16)
                LayerToggleRow(title: "Ortswerte",
                               subtitle: "Temperatur & Wind an Städten",
                               isOn: $settingsService.mapValueBubbles)
                Divider().padding(.leading, 16)
                LayerToggleRow(title: "Wetterwarnungen",
                               subtitle: "Aktive Warngebiete des DWD",
                               isOn: $settingsService.showAlertPolygons)
                Divider().padding(.leading, 16)
                LayerToggleRow(title: "Regenzellen",
                               subtitle: "Zugbahnen kräftiger Schauer",
                               isOn: $settingsService.showStormCells)
                LayerToggleRow(title: "Niederschlagsart",
                               subtitle: precipTypeAvailable
                                   ? "Schnee, Graupel & Hagel im Radar einfärben"
                                   : "Für das Europa-Radar (OPERA) nicht verfügbar",
                               isOn: $settingsService.radarPrecipTypeOverlay)
                    .disabled(true)//!precipTypeAvailable)
                    .opacity(precipTypeAvailable ? 1 : 0.45)
                Divider().padding(.leading, 16)
                opacityRow
                Divider().padding(.leading, 16)
                basemapRow
            }
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var opacityRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Deckkraft")
                Spacer()
                Text("\(Int((settingsService.mapOverlayOpacity * 100).rounded())) %")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $settingsService.mapOverlayOpacity, in: 0.3...1.0, step: 0.05)
                .accessibilityLabel(Text("Deckkraft der Wetterebenen"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var basemapRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Karte")
                Text("Stil der Hintergrundkarte")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Karte", selection: $settingsService.mapBasemapStyle) {
                ForEach(MapBasemapStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 190)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Selection

    private func isRadarSelected(_ region: RadarRegion) -> Bool {
        settingsService.oscarRadarLayer
            && settingsService.oscarRadarRegion == region
    }

    private func select(_ activate: () -> Void) {
        UIApplication.shared.playHapticFeedback()
        activate()
        // Picking a layer is the sheet's terminal action — close it so the map
        // is immediately visible; the display toggles keep the sheet open.
        dismissSheet()
    }
}

/// Section header row: semibold title, optionally followed by an info symbol —
/// with `onInfoTap` the whole title cluster becomes a button (the forecast
/// sections link to the weather-model explainer). The trailing edge carries an
/// optional secondary detail, e.g. the pulsing red "live" dot for the radar
/// section.
struct LayerPickerSectionHeader: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    var infoSymbol: String?
    var showsLiveDot = false
    var onInfoTap: (() -> Void)?

    var body: some View {
        HStack {
            if let onInfoTap {
                Button(action: onInfoTap) {
                    titleLabel
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Öffnet die Erklärung zu Wettermodellen"))
            } else {
                titleLabel
            }
            Spacer()
            if let detail {
                detailLabel(detail)
            }
        }
    }

    private var titleLabel: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let infoSymbol {
                Image(systemName: infoSymbol)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }

    private func detailLabel(_ detail: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            if showsLiveDot {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
            }
            Text(detail)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// One square layer tile, Apple-Maps-Kartenmodi-style: screenshot artwork with a
/// hairline rim, accent selection ring with a small gap, caption label below.
struct LayerTile: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let imageName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                artwork
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var artwork: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
            )
            .padding(3)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                }
            }
    }
}

/// Toggle row inside the "Darstellung" card: title + caption subtitle.
struct LayerToggleRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private extension WeatherTileLayer {
    /// Tile label in the layer picker (the product lives in the section header).
    var pickerRegion: LocalizedStringKey {
        switch self {
        case .iconPrecip, .iconTemp, .iconWind: return "Zentraleuropa"
        case .gfsPrecip, .gfsTemp, .gfsWind:    return "Weltweit"
        }
    }

    /// Preview screenshot in Assets.xcassets/LayerPreviews.
    var previewImageName: String {
        switch self {
        case .iconPrecip: return "layer-icon-precip"
        case .iconTemp:   return "layer-icon-temp"
        case .iconWind:   return "layer-icon-wind"
        case .gfsPrecip:  return "layer-gfs-precip"
        case .gfsTemp:    return "layer-gfs-temp"
        case .gfsWind:    return "layer-gfs-wind"
        }
    }
}
