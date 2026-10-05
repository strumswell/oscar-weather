//
//  MapPreview.swift
//  Oscar°
//
//  The forecast stage's map on wide windows: the layer Karten last showed,
//  at the current frame, without controls. A tap opens Karten.
//

import SwiftUI

struct MapPreview: View {
    @Environment(Location.self) private var location
    @Environment(NowPresentationCoordinator.self) private var presentation
    @State private var layers = MapLayers()
    private let settingsService = SettingService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NowSectionHeader(showMore: openMaps) {
                Text("Karte")
            }
            .padding(.bottom)

            Button(action: openMaps) {
                map
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Karte"))
            .accessibilityHint(Text("Öffnet Karten"))
            .padding(.horizontal)
        }
        .task(id: "\(location.coordinates.latitude)|\(location.coordinates.longitude)") {
            layers.pickRadarSource(for: location.coordinates)
            layers.syncCloudActivation()
            await layers.loadActiveLayer()
            await layers.loadContinuation(layers.continuation)
            await layers.refreshCityChips()
            await layers.keepFresh()
        }
        .onDisappear {
            layers.pause()
        }
    }

    private var map: some View {
        WeatherMapView(
            settingsService: settingsService,
            coordinates: location.coordinates,
            cities: LocationService.shared.city.cities,
            overlayOpacity: settingsService.mapOverlayOpacity,
            oscarRadarState: layers.radar,
            modelGridState: layers.model,
            cloudLayerState: layers.clouds,
            combinedTimeline: layers.timeline
        )
        .allowsHitTesting(false)
        .overlay(alignment: .topLeading) {
            MapLegendStack(settingsService: settingsService,
                           timeline: layers.timeline,
                           cloudLayerState: layers.clouds,
                           modelGridState: layers.model)
                .padding(12)
        }
        .overlay(alignment: .bottomLeading) {
            MapAttributionLabel()
                .padding(10)
        }
        .clipShape(.rect(cornerRadius: 10))
        .cardBorder()
        .contentShape(.rect)
    }

    private func openMaps() {
        Haptics.impact()
        presentation.selectedTab = .maps
    }
}
