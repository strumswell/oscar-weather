//
//  WeatherSimulationView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 02.01.24.
//

import CoreLocation
import SwiftUI

struct WeatherSimulationView: View {
    /// Another tab is in front, so the sim is fully hidden and animated layers
    /// drop to the background frame rate. Sheets deliberately don't count:
    /// iOS keeps the dimmed base view visible behind them, and the throttled
    /// rate reads as jank there.
    var isOffTab = false
    /// Renders this snapshot instead of deriving one for "now" — the hourly detail
    /// stage drives the sim with scrubbed hours through this. Same mechanism as
    /// the debug override (which still wins while debugging).
    var snapshotOverride: AtmosphereSnapshot? = nil
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location
    @Environment(AtmosphereDebugState.self) private var debugState: AtmosphereDebugState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Memoizes the derived snapshot so a per-observation body re-eval doesn't redo the mapper
    // every time; it recomputes only when the weather data, location, or a coarse time bucket
    // changes. body still reads forecast.hourly + lastUpdated, so observation stays intact and a
    // data change always invalidates the cache.
    @State private var snapshotCache = AtmosphereSnapshotCache()
    @State private var powerThrottled = Self.isPowerThrottled

    /// Low Power Mode or a hot device drops the animated layers to the
    /// background frame rate instead of running at full refresh.
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
            ?? MoonPhase.phaseFraction(for: Date(timeIntervalSince1970: snapshot.timestamp))
        let cloudThickness = snapshot.cloudThickness
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
                    // How much the moon brightens the night: phase × altitude.
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
                    if starOpacity > 0.02 {
                        // StarsView's internal fade follows the wall clock;
                        // under a scrub override the snapshot's night drives
                        // the outer opacity instead.
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
                    }

                    // Scrub steps land ~10 Hz; a matching linear tween turns
                    // the stepped sun/moon positions into continuous motion.
                    let celestialTween: Animation? = snapshotOverride != nil
                        ? .linear(duration: 0.15)
                        : nil

                    if let moonProgress, let moonLayout {
                        MoonView(
                            phase: moonPhase,
                            altitudeProgress: moonProgress,
                            xFraction: moonLayout.x,
                            yFraction: moonLayout.y,
                            isSouthernHemisphere: location.coordinates.latitude < 0,
                            skyDarkness: Double(snapshot.nightAmount)
                        )
                        // Realistic daytime visibility: a moon far enough from the sun with
                        // enough lit surface shows as a pale disc; a thin crescent near the sun
                        // fades to nothing, matching what's actually out the window. Full strength
                        // at night. Clouds dim and blur it (below) but never hide it outright.
                        .opacity(
                            MoonPhase.skyVisibility(phase: moonPhase, nightAmount: Double(snapshot.nightAmount))
                                * Double(1 - snapshot.cloudDensity * 0.4)
                        )
                        .blur(radius: CGFloat(snapshot.cloudDensity) * 2.5)
                        .animation(celestialTween, value: snapshot.timestamp)
                    }

                    if snapshot.showsSunDisc {
                        SunView(progress: Double(snapshot.timeOfDay))
                            .opacity(Double((1 - snapshot.cloudDensity * 0.45) * snapshot.phase * snapshot.sunDiscVisibility))
                            .animation(celestialTween, value: snapshot.timestamp)
                    }

                    // Under scrub the fade must stay short: long cross-fades
                    // overlap two translucent cloud decks during fast pans,
                    // which reads as shadowy flicker.
                    let deckTransition: Animation = snapshotOverride == nil
                        ? .easeInOut(duration: 0.8)
                        : .easeInOut(duration: 0.18)
                    ZStack {
                        if cloudsVisible {
                            CloudsView(
                                thickness: cloudThickness,
                                topTint: AtmosphereSampler.cloudTopTint(snapshot: snapshot, moonGlow: moonGlow),
                                bottomTint: AtmosphereSampler.cloudBottomTint(snapshot: snapshot, moonGlow: moonGlow),
                                pacing: pacing
                            )
                            .id(cloudThickness)
                            .transition(.opacity)
                            .opacity(Double(min(1, snapshot.cloudDensity + snapshot.cloudCoverage * 0.25)))
                        }
                    }
                    .animation(deckTransition, value: cloudThickness)
                    .animation(deckTransition, value: cloudsVisible)

                    // Fog banks sit in front of the clouds, near the ground.
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
                    // No forecast yet (first launch, or a failed cold-start fetch): a calm
                    // starry twilight rather than an empty gradient. The retry affordance lives
                    // in NowView; this is purely the backdrop.
                    AtmosphereSkyShaderView(snapshot: snapshot, size: proxy.size, pacing: pacing)

                    let starOpacity = Double(snapshot.nightAmount)
                    if starOpacity > 0.02 {
                        StarsView(pacing: pacing)
                            .opacity(starOpacity)
                    }
                }

                #if DEBUG
                if weather.debug {
                    AtmosphereDebugOverlay(snapshot: snapshot)
                }
                #endif
            }
            .preferredColorScheme(.dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AtmosphereSampler.skyGradient(snapshot: snapshot))
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: DispatchQueue.main)) { _ in
            powerThrottled = Self.isPowerThrottled
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification).receive(on: DispatchQueue.main)) { _ in
            powerThrottled = Self.isPowerThrottled
        }
        .ignoresSafeArea()
    }

    /// The moon's pass across the sky (0 = rise, 0.5 = transit, 1 = set),
    /// or nil when it's below the horizon, the phase is too new to see, or
    /// clouds hide it. Visible day and night, like the real moon.
    /// Plain debug mode pins the moon at transit for visual checks; with
    /// overrides active it follows the scrubbed time and phase naturally.
    private func moonAltitudeProgress(
        _ snapshot: AtmosphereSnapshot,
        phase: Double,
        overriding: Bool
    ) -> Double? {
        #if DEBUG
        if weather.debug && !overriding {
            return 0.5
        }
        #endif

        // Never hard-gate on cloud cover: the moon stays visible even in full overcast (the
        // opacity + blur on MoonView dim and soften it through the clouds). Only suppress it when
        // the phase is too thin to be worth rendering.
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
