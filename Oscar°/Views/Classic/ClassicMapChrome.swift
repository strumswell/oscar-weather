//
//  ClassicMapChrome.swift
//  Oscar°
//
//  iOS 6 chrome over the weather map: a dark bar with the layer's name, the
//  frame time and a blue "Fertig"; a toolbar with locate, play/pause and one
//  segment per layer. Same layers and playback as the modern map; the map
//  page below owns the states and the loading.
//

import SwiftUI

struct ClassicMapChrome: View {
    let settingsService: SettingService
    let radarState: OscarRadarState
    let modelGridState: ModelGridLayerState
    let cloudLayerState: CloudLayerState
    let onSelectRadar: (RadarRegion) -> Void
    let onSelectTileLayer: (WeatherTileLayer) -> Void
    let onSelectClouds: () -> Void
    let onDone: () -> Void

    private enum Layer: CaseIterable {
        case radar, clouds, precip, temp, wind, pressure

        var title: LocalizedStringKey {
            switch self {
            case .radar: "Radar"
            case .clouds: "Wolken"
            case .precip: "Regen"
            case .temp: "Temperatur"
            case .wind: "Wind"
            case .pressure: "Luftdruck"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            MapAttributionLabel()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)
                .padding(.bottom, 4)
            toolbar
        }
    }

    // MARK: - Bars

    private var topBar: some View {
        ZStack {
            VStack(spacing: 0) {
                Text(selectedLayer.title)
                    .font(.custom("HelveticaNeue-Bold", fixedSize: 20))
                if let frameTime {
                    Text(verbatim: frameTime)
                        .font(.custom("HelveticaNeue-Bold", fixedSize: 12))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 0, y: -1)
            HStack {
                Spacer()
                Button(action: onDone) {
                    Text("Fertig")
                        .font(.custom("HelveticaNeue-Bold", fixedSize: 15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(classicBarButton(top: Color(red: 0.45, green: 0.62, blue: 0.9), bottom: Color(red: 0.1, green: 0.35, blue: 0.8)))
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(barGradient.ignoresSafeArea(edges: .top))
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                barButton(symbol: "location.fill") {
                    NotificationCenter.default.post(name: .mapCenterOnUser, object: nil)
                }
                .accessibilityLabel(Text("Auf meinen Standort zentrieren"))
                barButton(symbol: player?.isPlaying == true ? "pause.fill" : "play.fill") {
                    guard let player else { return }
                    player.isPlaying ? player.pause() : player.play()
                }
                .accessibilityLabel(Text(player?.isPlaying == true ? "Pause" : "Abspielen"))
                timeSlider
            }
            .disabled(player?.hasAnyLoadedFrame != true)
            ScrollView(.horizontal) {
                HStack(spacing: 1) {
                    ForEach(Layer.allCases, id: \.self) { layer in
                        segment(layer)
                    }
                }
                .clipShape(.rect(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.black.opacity(0.5), lineWidth: 1))
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(barGradient.ignoresSafeArea(edges: .bottom))
    }

    /// Manual scrubbing through the frames; the player's own scrub hooks
    /// pause playback while the thumb is held.
    private var timeSlider: some View {
        let count = player?.frameTimestamps.count ?? 0
        let index = Binding<Double>(
            get: { Double(player?.currentFrameIndex ?? 0) },
            set: { value in
                let next = Int(value.rounded())
                guard let player, next != player.currentFrameIndex else { return }
                player.currentFrameIndex = next
            }
        )
        let range = 0...Double(max(count - 1, 1))
        return ClassicSlider(value: index, in: range) { editing in
            editing ? player?.beginScrubbing() : player?.endScrubbing()
        }
        .accessibilityRepresentation {
            Slider(value: index, in: range, step: 1)
                .accessibilityLabel(Text("Zeitpunkt"))
                .accessibilityValue(Text(verbatim: frameTime ?? ""))
        }
    }

    private var barGradient: some View {
        LinearGradient(colors: [Color(white: 0.32), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
    }

    private func barButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 34)
                .background(classicBarButton(top: Color(white: 0.3), bottom: Color(white: 0.05)))
        }
    }

    private func segment(_ layer: Layer) -> some View {
        let selected = layer == selectedLayer
        return Button {
            select(layer)
        } label: {
            Text(layer.title)
                .font(.custom("HelveticaNeue-Bold", fixedSize: 14))
                .foregroundStyle(selected ? .white : Color(white: 0.3))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    selected
                        ? LinearGradient(colors: [Color(red: 0.55, green: 0.7, blue: 0.95), Color(red: 0.2, green: 0.45, blue: 0.9)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color(white: 0.98), Color(white: 0.85)], startPoint: .top, endPoint: .bottom)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Layers and playback

    private var selectedLayer: Layer {
        if settingsService.oscarRadarLayer { return .radar }
        if settingsService.cloudLayerActive { return .clouds }
        switch settingsService.activeTileLayer {
        case .iconPrecip, .ecmwfPrecip: return .precip
        case .iconTemp, .ecmwfTemp: return .temp
        case .iconWind, .ecmwfWind: return .wind
        case .iconPressure, .ecmwfPressure: return .pressure
        case nil: return .radar
        }
    }

    private func select(_ layer: Layer) {
        // ponytail: no model picker; ICON-D2 covers the DWD radar region,
        // everywhere else gets the global ECMWF product.
        let global = settingsService.oscarRadarRegion != .germany
        switch layer {
        case .radar: onSelectRadar(settingsService.oscarRadarRegion)
        case .clouds: onSelectClouds()
        case .precip: onSelectTileLayer(global ? .ecmwfPrecip : .iconPrecip)
        case .temp: onSelectTileLayer(global ? .ecmwfTemp : .iconTemp)
        case .wind: onSelectTileLayer(global ? .ecmwfWind : .iconWind)
        case .pressure: onSelectTileLayer(global ? .ecmwfPressure : .iconPressure)
        }
    }

    private var player: (any TimelinePlayerState)? {
        if settingsService.oscarRadarLayer { return radarState }
        if settingsService.cloudLayerActive { return cloudLayerState }
        if settingsService.activeTileLayer != nil { return modelGridState }
        return nil
    }

    private var frameTime: String? {
        guard let player, player.frameTimestamps.indices.contains(player.currentFrameIndex),
              let date = parseFrameDate(player.frameTimestamps[player.currentFrameIndex])
        else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// The iOS 6 slider: inset groove, glossy blue fill, silver knob. Snaps to
/// whole steps; `onEditingChanged` brackets the drag like SwiftUI's Slider.
struct ClassicSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void

    init(value: Binding<Double>, in range: ClosedRange<Double>, onEditingChanged: @escaping (Bool) -> Void) {
        _value = value
        self.range = range
        self.onEditingChanged = onEditingChanged
    }

    @State private var isDragging = false

    private static let knob: CGFloat = 23
    private static let track: CGFloat = 9

    var body: some View {
        GeometryReader { geometry in
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
            let travel = geometry.size.width - Self.knob
            let x = Self.knob / 2 + travel * fraction
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.45), Color(white: 0.7)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(.black.opacity(0.45), lineWidth: 1))
                    .frame(height: Self.track)
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.72, blue: 0.95), Color(red: 0.15, green: 0.4, blue: 0.85)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(.black.opacity(0.3), lineWidth: 1))
                    .frame(width: x + Self.track / 2, height: Self.track)
                Circle()
                    .fill(LinearGradient(colors: [.white, Color(white: 0.82)], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(Color(white: 0.4), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1.5)
                    .frame(width: Self.knob, height: Self.knob)
                    .position(x: x, y: geometry.size.height / 2)
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let dragged = min(max((drag.location.x - Self.knob / 2) / max(travel, 1), 0), 1)
                        value = (range.lowerBound + dragged * span).rounded()
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: Self.knob)
    }
}
