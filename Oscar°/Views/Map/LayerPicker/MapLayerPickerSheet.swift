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

struct MapLayerPickerSheet: View {
    @Bindable var settingsService: SettingService
    let onSelectRadar: (RadarRegion) -> Void
    let onSelectTileLayer: (WeatherTileLayer) -> Void
    let onSelectClouds: () -> Void
    @Environment(\.dismiss) private var dismissSheet
    @State private var showsModelInfo = false
    @State private var showsRadarInfo = false
    @State private var showsSatelliteInfo = false

    private static let tileColumns = Array(
        repeating: GridItem(.flexible(), spacing: 12), count: 4)
    private static let radarTileWidth: CGFloat = 76

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 16) {
                        LayerPickerGroupHeader(title: "Messung",
                                               caption: "Live gemessen, mit Kurzprognose",
                                               showsLiveDot: true)
                        radarSection
                        satelliteSection
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        LayerPickerGroupHeader(title: "Vorhersage",
                                               caption: "Berechnet von Wettermodellen",
                                               onInfoTap: { showsModelInfo = true })
                        modelRow(title: "Zentraleuropa", detail: "DWD ICON-D2 · ≈ 2 km",
                                 layers: [.iconPrecip, .iconTemp, .iconWind, .iconPressure])
                        modelRow(title: "Weltweit", detail: "ECMWF IFS · ≈ 9 km",
                                 layers: [.ecmwfPrecip, .ecmwfTemp, .ecmwfWind, .ecmwfPressure])
                    }
                    displaySection
                    attributionFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .navigationTitle("Kartenebenen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
            .navigationDestination(isPresented: $showsSatelliteInfo) {
                SatelliteInfoView()
            }
        }
    }

    // MARK: Sections

    private var radarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LayerPickerSectionHeader(title: "Radar", detail: nil,
                                     infoSymbol: "info.circle",
                                     infoHint: "Öffnet Details zu den Radarquellen",
                                     onInfoTap: { showsRadarInfo = true })
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
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
                        radarTile(.canarias, title: "Kanaren", subtitle: "AEMET",
                                  imageName: "layer-radar-canarias")
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .onAppear {
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

    private var satelliteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LayerPickerSectionHeader(title: "Satellit", detail: nil,
                                     infoSymbol: "info.circle",
                                     infoHint: "Öffnet Details zur Satellitenquelle",
                                     onInfoTap: { showsSatelliteInfo = true })
            LazyVGrid(columns: Self.tileColumns, spacing: 14) {
                LayerTile(title: "Wolken", subtitle: "Meteosat",
                          imageName: "layer-clouds",
                          isSelected: settingsService.cloudLayerActive,
                          action: { select { onSelectClouds() } })
            }
        }
    }

    private func modelRow(title: LocalizedStringKey, detail: LocalizedStringKey,
                          layers: [WeatherTileLayer]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LayerPickerSectionHeader(title: title, detail: detail)
            LazyVGrid(columns: Self.tileColumns, spacing: 14) {
                ForEach(layers, id: \.self) { layer in
                    LayerTile(title: layer.productTitle, subtitle: nil,
                              imageName: layer.previewImageName,
                              isSelected: settingsService.activeTileLayer == layer,
                              action: { select { onSelectTileLayer(layer) } })
                }
            }
        }
    }

    private var attributionFooter: some View {
        VStack(spacing: 12) {
            HStack(spacing: 18) {
                ProviderLogo(asset: "logo-dwd", height: 28)
                ProviderLogo(asset: "logo-ecmwf", height: 18)
                ProviderLogo(asset: "logo-eumetnet", height: 28)
                ProviderLogo(asset: "logo-noaa", height: 28)
            }
            Text("Contains modified EUMETSAT Meteosat data \(String(Calendar.current.component(.year, from: Date())))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            PoweredByOscarServer(lockupHeight: 32)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var isobarsAvailable: Bool {
        settingsService.activeTileLayer != nil
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LayerPickerSectionHeader(title: "Darstellung", detail: nil)
                .accessibilityIdentifier("map.layers.display")
            VStack(spacing: 0) {
                LayerToggleRow(title: "Flüssige Bewegungen",
                               subtitle: "Sanfte Übergänge zwischen den Bildern",
                               isOn: $settingsService.radarSmoothMotion)
                Divider().padding(.leading, 16)
                LayerToggleRow(title: "Weichzeichnen",
                               subtitle: "Weiche Kanten statt harter Farbstufen",
                               isOn: $settingsService.radarSoftRendering)
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
        activate()
        dismissSheet()
    }
}

private extension WeatherTileLayer {
    var productTitle: LocalizedStringKey {
        switch self {
        case .iconPrecip, .ecmwfPrecip: "Regen"
        case .iconTemp, .ecmwfTemp: "Temperatur"
        case .iconWind, .ecmwfWind: "Wind"
        case .iconPressure, .ecmwfPressure: "Luftdruck"
        }
    }

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

extension View {
    func layerPickerInspector(
        isPresented: Binding<Bool>,
        settingsService: SettingService,
        select: @escaping (RadarRegion?, WeatherTileLayer?) -> Void
    ) -> some View {
        inspector(isPresented: isPresented) {
            MapLayerPickerSheet(
                settingsService: settingsService,
                onSelectRadar: { select($0, nil) },
                onSelectTileLayer: { select(nil, $0) },
                onSelectClouds: { select(nil, nil) }
            )
            .presentationDetents([.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationDragIndicator(.hidden)
            .inspectorColumnWidth(min: 320, ideal: 360, max: 420)
            .onDisappear { isPresented.wrappedValue = false }
        }
    }
}
