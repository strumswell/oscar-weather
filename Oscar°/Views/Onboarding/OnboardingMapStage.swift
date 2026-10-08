//
//  OnboardingMapStage.swift
//  Oscar°
//

import CoreLocation
import SwiftUI

/// The radar page's picture: the real map over Leipzig. It starts on the
/// screenshot run's replayed radar composite (real echoes, no network), then
/// steps through live model layers, with the map's own timeline controls.
struct OnboardingMapStage: View {
    /// Frames already being built (started by the features step's first
    /// page); nil builds them here.
    var prebuiltGrids: Task<[[UInt8]], Never>?

    @State private var radar = OscarRadarState()
    @State private var model = ModelGridLayerState()
    @State private var selection = 0
    /// The layer whose countdown runs: set once its data is on the map.
    @State private var countingSelection: Int?

    private static let leipzig = CLLocationCoordinate2D(latitude: 51.3397, longitude: 12.3731)
    /// nil = radar.
    private static let layers: [WeatherTileLayer?] = [nil, .iconTemp, .iconWind, .iconPressure]
    private static let titles: [LocalizedStringKey] = ["Regenradar", "Temperatur", "Wind", "Luftdruck"]
    private static let secondsPerLayer = 10.0

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
            layerOverride: MapLayerOverride(radar: tileLayer == nil, tileLayer: tileLayer)
        )
        .allowsHitTesting(false)
        .overlay(alignment: .bottomLeading) {
            MapAttributionLabel()
                .padding(10)
        }
        .clipShape(.rect(cornerRadius: 24))
        .overlay(alignment: .top) {
            LayerTabs(
                titles: Self.titles,
                current: selection,
                isCounting: countingSelection == selection,
                duration: Self.secondsPerLayer
            ) { index in
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

    /// Plays one layer, then moves on to the next after a few seconds. The
    /// time starts once the layer is loaded, so a slow network never skips one.
    private func show(_ layer: WeatherTileLayer?) async {
        countingSelection = nil
        if let layer {
            radar.pause()
            await model.loadLayer(layer)
            guard !Task.isCancelled else { return }
            model.play()
        } else {
            model.pause()
            // The first pass waits for the staged frames to be built.
            while !radar.hasAnyLoadedFrame {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
            }
            radar.play()
        }
        countingSelection = selection
        try? await Task.sleep(for: .seconds(Self.secondsPerLayer))
        guard !Task.isCancelled else { return }
        selection = (selection + 1) % Self.layers.count
    }

    /// The replayed radar's value grids, from now to two hours ahead in
    /// five-minute steps, built in parallel off the main actor.
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

    /// Turns the grids into frames timed from now and hands them to the map.
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

    /// The fixture's flow field through the same decoder the server's goes
    /// through; nil just means a plain cross-fade between frames.
    private static func stagedMotion() -> RadarMotionData? {
        guard let json = try? JSONSerialization.data(withJSONObject: SyntheticRadar.motionJSON()),
              let payload = try? JSONDecoder().decode(Components.Schemas.MotionResponse.self, from: json)
        else { return nil }
        return RadarMotionData(payload: payload)
    }
}

/// The layers as a segmented pill over the map. The current one shows a
/// thin countdown line once its data is loaded; tapping jumps to a layer.
private struct LayerTabs: View {
    let titles: [LocalizedStringKey]
    let current: Int
    let isCounting: Bool
    let duration: Double
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
                        .overlay(alignment: .bottom) {
                            if isCurrent && isCounting {
                                // A fresh view per layer, so the line restarts at zero.
                                Countdown(duration: duration)
                                    .id(current)
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 3)
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

private struct Countdown: View {
    let duration: Double

    @State private var filled = false

    var body: some View {
        Capsule()
            .fill(.black.opacity(0.12))
            .frame(height: 2)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.black.opacity(0.45))
                    .scaleEffect(x: filled ? 1 : 0, anchor: .leading)
            }
            .onAppear {
                withAnimation(.linear(duration: duration)) {
                    filled = true
                }
            }
    }
}
