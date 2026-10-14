//
//  WeatherSimulationView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 02.01.24.
//

import CoreLocation
import SwiftUI

struct WeatherSimulationView: View, Animatable {
    var isOffTab = false
    nonisolated var snapshotOverride: AtmosphereSnapshot? = nil
    nonisolated var animatableData: AtmosphereSnapshot.Vector {
        get { snapshotOverride?.vector ?? .zero }
        set {
            guard let current = snapshotOverride else { return }
            snapshotOverride = AtmosphereSnapshot(vector: newValue, condition: current.condition)
        }
    }
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location
    @Environment(AtmosphereDebugState.self) private var debugState: AtmosphereDebugState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshotCache = AtmosphereSnapshotCache()
    @State private var powerThrottled = Self.isPowerThrottled

    private static var isPowerThrottled: Bool {
        let info = ProcessInfo.processInfo
        return info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical
    }

    var body: some View {
        let overrides = (weather.debug && debugState?.overrideEnabled == true) ? debugState : nil
        let hasContent = snapshotOverride != nil || weather.forecast.hourly != nil || overrides != nil
        let snapshot = overrides?.snapshot
            ?? snapshotOverride
            ?? (weather.forecast.hourly != nil
                ? snapshotCache.snapshot(from: weather, at: location.coordinates)
                : .twilight)
        let moonPhase = overrides?.moonPhase
            ?? (MoonPhase.phaseFraction(for: Date(timeIntervalSince1970: snapshot.timestamp)) * 512).rounded() / 512
        let cloudsVisible = snapshot.cloudDensity + snapshot.cloudCoverage > 0.02
        let pacing: SimulationPacing = reduceMotion || isOffTab ? .still : (powerThrottled ? .background : .active)

        GeometryReader { proxy in
            ZStack {
                if hasContent {
                    let moonProgress = moonAltitudeProgress(
                        snapshot,
                        phase: moonPhase,
                        overriding: overrides != nil
                    )
                    let moonLayout = moonProgress.map { progress in
                        (
                            x: 0.12 + 0.76 * progress,
                            y: 0.345 - 0.135 * sin(.pi * progress)
                        )
                    }
                    let moonGlow = moonProgress.map {
                        Float(MoonPhase.illumination(for: moonPhase))
                            * snapshot.nightAmount
                            * Float(sin(.pi * $0))
                    } ?? 0

                    AtmosphereSkyShaderView(
                        snapshot: snapshot,
                        size: proxy.size,
                        moonGlow: moonGlow,
                        pacing: pacing
                    )

                    let starOpacity = Double(snapshot.nightAmount)
                        * Double(1 - snapshot.cloudCoverage * 0.85)
                    let presenceFade: Animation = .easeInOut(duration: 0.4)
                    ZStack {
                        if starOpacity > 0.02 {
                            StarsView(
                                pacing: pacing,
                                occlusionCenter: moonLayout.map {
                                    CGPoint(
                                        x: proxy.size.width * $0.x,
                                        y: proxy.size.height * $0.y
                                    )
                                },
                                occlusionRadius: MoonView.diameter / 2 + 8,
                                opacityOverride: snapshotOverride != nil ? 1 : nil
                            )
                            .opacity(starOpacity)
                            .transition(.opacity)
                        }
                    }
                    .animation(presenceFade, value: starOpacity > 0.02)

                    ZStack {
                        if let moonProgress, let moonLayout {
                            MoonView(
                                phase: moonPhase,
                                altitudeProgress: moonProgress,
                                xFraction: moonLayout.x,
                                yFraction: moonLayout.y,
                                isSouthernHemisphere: location.coordinates.latitude < 0,
                                skyDarkness: Double(snapshot.nightAmount)
                            )
                            .opacity(
                                MoonPhase.skyVisibility(phase: moonPhase, nightAmount: Double(snapshot.nightAmount))
                                    * Double(1 - snapshot.moonVeil * 0.4)
                            )
                            .blur(radius: (CGFloat(snapshot.moonVeil) * 10).rounded() / 4)
                            .transition(.opacity)
                        }
                    }
                    .animation(presenceFade, value: moonProgress != nil)

                    ZStack {
                        if snapshot.showsSunDisc {
                            SunView(progress: Double(snapshot.timeOfDay))
                                .opacity(Double((1 - snapshot.cloudDensity * 0.45) * snapshot.phase * snapshot.sunDiscVisibility))
                                .transition(.opacity)
                        }
                    }
                    .animation(presenceFade, value: snapshot.showsSunDisc)

                    let deckTransition: Animation = snapshotOverride == nil
                        ? .easeInOut(duration: 0.8)
                        : .easeInOut(duration: 0.18)
                    ZStack {
                        if cloudsVisible {
                            CloudsView(
                                deck: snapshot.cloudDeck,
                                drift: snapshot.cloudDrift,
                                lightDirection: snapshot.cloudLightDirection,
                                topTint: AtmosphereSampler.cloudTopTint(snapshot: snapshot, moonGlow: moonGlow),
                                bottomTint: AtmosphereSampler.cloudBottomTint(snapshot: snapshot, moonGlow: moonGlow),
                                pacing: pacing
                            )
                            .transition(.opacity)
                            .opacity(Double(min(1, snapshot.cloudDensity + snapshot.cloudCoverage * 0.25)))
                        }
                    }
                    .animation(deckTransition, value: cloudsVisible)

                    let fogVisible = snapshot.condition == .fog
                    ZStack {
                        if fogVisible {
                            FogView(
                                density: Double(snapshot.haze),
                                nightAmount: Double(snapshot.nightAmount),
                                pacing: pacing
                            )
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: snapshotOverride == nil ? 1.2 : 0.3), value: fogVisible)

                    let stormVisible = snapshot.showsPrecipitation
                    ZStack {
                        if stormVisible {
                            StormView(
                                type: snapshot.stormContents,
                                direction: snapshot.stormSlant,
                                strength: snapshot.stormStrength(rainBase: 45, snowBase: 90, weight: 170, floor: 12, cap: 220),
                                pacing: pacing
                            )
                            .id(String(describing: snapshot.stormContents))
                            .transition(.opacity)
                            .opacity(reduceMotion ? 0.55 : 1)
                        }
                    }
                    .animation(.easeInOut(duration: snapshotOverride == nil ? 0.8 : 0.25), value: stormVisible)
                } else {
                    AtmosphereSkyShaderView(snapshot: snapshot, size: proxy.size, pacing: pacing)

                    let starOpacity = Double(snapshot.nightAmount)
                    if starOpacity > 0.02 {
                        StarsView(pacing: pacing)
                            .opacity(starOpacity)
                    }
                }

                if weather.debug {
                    AtmosphereDebugOverlay(snapshot: snapshot)
                }
            }
            .preferredColorScheme(.dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: DispatchQueue.main)) { _ in
            powerThrottled = Self.isPowerThrottled
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification).receive(on: DispatchQueue.main)) { _ in
            powerThrottled = Self.isPowerThrottled
        }
        .ignoresSafeArea()
    }

    private func moonAltitudeProgress(
        _ snapshot: AtmosphereSnapshot,
        phase: Double,
        overriding: Bool
    ) -> Double? {
        if weather.debug && !overriding {
            return 0.5
        }

        guard MoonPhase.illumination(for: phase) >= 0.05 else {
            return nil
        }

        return MoonPhase.skyProgress(
            date: Date(timeIntervalSince1970: snapshot.timestamp),
            latitude: location.coordinates.latitude,
            longitude: location.coordinates.longitude
        )
    }

}

#Preview {
    WeatherSimulationView()
        .environment(Weather.mock)
        .environment(Location())
}
