//
//  OnboardingMapStage.swift
//  Oscar°
//

import CoreLocation
import SwiftUI

struct OnboardingMapStage: View {
    var prebuiltGrids: Task<[[UInt8]], Never>?

    @State private var radar = OscarRadarState()
    @State private var model = ModelGridLayerState()
    @State private var selection = 0

    private static let leipzig = CLLocationCoordinate2D(latitude: 51.3397, longitude: 12.3731)
    private static let layers: [WeatherTileLayer?] = [nil, .iconTemp, .iconWind, .iconPressure]
    private static let titles: [LocalizedStringKey] = ["Regenradar", "Temperatur", "Wind", "Luftdruck"]

    private var tileLayer: WeatherTileLayer? { Self.layers[selection] }

    var body: some View {
        VStack(spacing: 8) {
            map
            controls
        }
        .task { await stageRadar() }
        .task(id: selection) { await show(Self.layers[selection]) }
        .onDisappear {
            radar.pause()
            model.pause()
        }
    }

    private var map: some View {
        WeatherMapView(
            settingsService: .shared,
            coordinates: Self.leipzig,
            cities: [],
            overlayOpacity: SettingService.shared.mapOverlayOpacity,
            oscarRadarState: radar,
            modelGridState: model,
            cloudLayerState: nil,
            layerOverride: MapLayerOverride(radar: tileLayer == nil, tileLayer: tileLayer),
            startZoom: 5.5
        )
        .allowsHitTesting(false)
        .overlay(alignment: .bottomLeading) {
            MapAttributionLabel()
                .padding(10)
        }
        .clipShape(.rect(cornerRadius: 24))
        .overlay(alignment: .top) {
            LayerTabs(titles: Self.titles, current: selection) { index in
                selection = index
            }
            .padding(10)
        }
    }

    @ViewBuilder private var controls: some View {
        if tileLayer == nil {
            TimelineControlsChip(
                state: radar,
                sourceLabel: radar.region.sourceLabel,
                shortSourceLabel: radar.region.shortSourceLabel,
                isLive: radar.isCurrentFrameLive,
                isForecast: false,
                loadingLabel: "Oscar Radar-Daten werden geladen…"
            )
        } else {
            WeatherTileTimelineControls(imageState: model)
        }
    }

    private func show(_ layer: WeatherTileLayer?) async {
        if let layer {
            radar.pause()
            await model.loadLayer(layer)
        } else {
            model.pause()
        }
    }

    nonisolated static func buildGrids() async -> [[UInt8]] {
        let offsets = SyntheticRadar.offsets
        return await withTaskGroup(of: (Int, [UInt8]).self) { group in
            for (index, offset) in offsets.enumerated() {
                group.addTask { (index, SyntheticRadar.radarGrid(minutes: Double(offset))) }
            }
            var grids = [[UInt8]](repeating: [], count: offsets.count)
            for await (index, grid) in group {
                grids[index] = grid
            }
            return grids
        }
    }

    private func stageRadar() async {
        let offsets = SyntheticRadar.offsets
        let grids = if let prebuiltGrids {
            await prebuiltGrids.value
        } else {
            await Self.buildGrids()
        }
        guard !Task.isCancelled else { return }

        let fiveMinutes = 5.0 * 60
        let start = Date(timeIntervalSinceReferenceDate: (Date.now.timeIntervalSinceReferenceDate / fiveMinutes).rounded(.down) * fiveMinutes)
        let dates = offsets.map { start.addingTimeInterval(Double($0) * 60) }
        let formatter = ISO8601DateFormatter()
        let frames = offsets.indices.map { index in
            OscarRadarFrame(
                key: SyntheticRadar.key(offsets[index]),
                timestamp: formatter.string(from: dates[index]),
                gridIndices: grids[index],
                width: SyntheticRadar.gridWidth,
                height: SyntheticRadar.gridHeight
            )
        }
        radar.showStagedFrames(
            frames,
            dates: dates,
            bounds: OscarRadarBounds(
                north: SyntheticRadar.north, south: SyntheticRadar.south,
                west: SyntheticRadar.west, east: SyntheticRadar.east
            ),
            motion: Self.stagedMotion()
        )
    }

    private static func stagedMotion() -> RadarMotionData? {
        guard let json = try? JSONSerialization.data(withJSONObject: SyntheticRadar.motionJSON()),
              let payload = try? JSONDecoder().decode(Components.Schemas.MotionResponse.self, from: json)
        else { return nil }
        return RadarMotionData(payload: payload)
    }
}

private struct LayerTabs: View {
    let titles: [LocalizedStringKey]
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(titles.indices, id: \.self) { index in
                let isCurrent = index == current
                Button {
                    onSelect(index)
                } label: {
                    Text(titles[index])
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(isCurrent ? .black : .white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isCurrent {
                                Capsule().fill(.white)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glassEffect(in: .capsule)
        .animation(.snappy, value: current)
    }
}
