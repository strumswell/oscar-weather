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
    @State private var showsRadarInfo = false

    private static let tileColumns = Array(
        repeating: GridItem(.flexible(), spacing: 12), count: 4)
    /// Radar tiles scroll horizontally (five coverages don't fit a row), so they
    /// need a fixed width — sized to the 4-column grid below on a compact phone,
    /// which leaves a peek of the next tile as the scroll affordance.
    private static let radarTileWidth: CGFloat = 76

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    radarSection
                    productSection(title: "Regen", layers: [.iconPrecip, .ecmwfPrecip])
                    productSection(title: "Temperatur", layers: [.iconTemp, .ecmwfTemp])
                    productSection(title: "Wind", layers: [.iconWind, .ecmwfWind])
                    productSection(title: "Luftdruck", layers: [.iconPressure, .ecmwfPressure])
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
            .navigationDestination(isPresented: $showsRadarInfo) {
                RadarInfoView()
            }
        }
        .task {
            // Testing hooks: `-autoPresentModelInfo YES` / `-autoPresentRadarInfo
            // YES` jump straight to the explainer pages (screenshot flows
            // without touch input).
            if UserDefaults.standard.bool(forKey: "autoPresentModelInfo") {
                showsModelInfo = true
            } else if UserDefaults.standard.bool(forKey: "autoPresentRadarInfo") {
                showsRadarInfo = true
            }
        }
    }

    // MARK: Sections

    private var radarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LayerPickerSectionHeader(title: "Radar", detail: "Live + Kurzprognose",
                                     infoSymbol: "info.circle",
                                     showsLiveDot: true,
                                     infoHint: "Öffnet Details zu den Radarquellen",
                                     onInfoTap: { showsRadarInfo = true })
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        radarTile(.germany, title: "Zentraleuropa", subtitle: "DWD",
                                  imageName: "layer-radar-germany")
                        radarTile(.europe, title: "Europa", subtitle: "EUMETNET",
                                  imageName: "layer-radar-europe")
                        radarTile(.usa, title: "USA", subtitle: "NOAA",
                                  imageName: "layer-radar-usa")
                        radarTile(.taiwan, title: "Taiwan", subtitle: "CWA",
                                  imageName: "layer-radar-taiwan")
                        radarTile(.brasil, title: "Brasilien", subtitle: "REDEMET",
                                  imageName: "layer-radar-brasil")
                    }
                }
                .scrollClipDisabled()
                .onAppear {
                    // A selected coverage at the row's end would otherwise open
                    // hidden behind the fold.
                    guard settingsService.oscarRadarLayer else { return }
                    proxy.scrollTo(settingsService.oscarRadarRegion, anchor: .trailing)
                }
            }
        }
    }

    private func radarTile(_ region: RadarRegion, title: LocalizedStringKey,
                           subtitle: LocalizedStringKey, imageName: String) -> some View {
        LayerTile(title: title, subtitle: subtitle,
                  imageName: imageName,
                  isSelected: isRadarSelected(region),
                  action: { select { onSelectRadar(region) } })
            .frame(width: Self.radarTileWidth)
            .id(region)
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

    /// The typed radar product exists for DWD and MRMS coverage, not OPERA or CWA.
    private var precipTypeAvailable: Bool {
        !settingsService.oscarRadarLayer
            || RadarProduct.precipitationTyped.isAvailable(in: settingsService.oscarRadarRegion)
    }

    /// Isobars ride the hourly model frames, so they need a model layer —
    /// the 5-minute radar timeline has no matching pressure fields.
    private var isobarsAvailable: Bool {
        settingsService.activeTileLayer != nil
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
                Divider().padding(.leading, 16)
                LayerToggleRow(title: "Isobaren",
                               subtitle: isobarsAvailable
                                   ? "Luftdrucklinien mit Hoch- und Tiefzentren"
                                   : "Nur auf Modellebenen (Radar hat keinen Luftdruck)",
                               isOn: $settingsService.showIsobars)
                    .disabled(!isobarsAvailable)
                    .opacity(isobarsAvailable ? 1 : 0.45)
                LayerToggleRow(title: "Niederschlagsart",
                               subtitle: precipTypeAvailable
                                   ? "Schnee, Graupel & Hagel im Radar einfärben"
                                   : "Für dieses Radar nicht verfügbar",
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
    var infoHint: LocalizedStringKey = "Öffnet die Erklärung zu Wettermodellen"
    var onInfoTap: (() -> Void)?

    var body: some View {
        HStack {
            if let onInfoTap {
                Button(action: onInfoTap) {
                    titleLabel
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text(infoHint))
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
        // Stock switch green; the tab's cascading label tint would paint the
        // track white/black.
        .tint(.green)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private extension WeatherTileLayer {
    /// Tile label in the layer picker (the product lives in the section header).
    var pickerRegion: LocalizedStringKey {
        switch self {
        case .iconPrecip, .iconTemp, .iconWind, .iconPressure: return "Zentraleuropa"
        case .ecmwfPrecip, .ecmwfTemp, .ecmwfWind, .ecmwfPressure: return "Weltweit"
        }
    }

    /// Preview screenshot in Assets.xcassets/LayerPreviews. The "gfs" names
    /// are historic — the artwork was captured from the retired GFS layers,
    /// which looked the same as ECMWF's global products.
    var previewImageName: String {
        switch self {
        case .iconPrecip:   return "layer-icon-precip"
        case .iconTemp:     return "layer-icon-temp"
        case .iconWind:     return "layer-icon-wind"
        case .iconPressure: return "layer-icon-pressure"
        case .ecmwfPrecip:  return "layer-gfs-precip"
        case .ecmwfTemp:    return "layer-gfs-temp"
        case .ecmwfWind:    return "layer-gfs-wind"
        case .ecmwfPressure: return "layer-gfs-pressure"
        }
    }
}
