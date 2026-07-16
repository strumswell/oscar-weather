//
//  WeatherSimulationView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 02.01.24.
//

import CoreLocation
import SwiftUI

struct WeatherSimulationView: View {
    var isCoveredBySheet = false
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location
    @Environment(AtmosphereDebugState.self) private var debugState: AtmosphereDebugState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Memoizes the derived snapshot so a per-observation body re-eval doesn't redo the mapper
    // every time; it recomputes only when the weather data, location, or a coarse time bucket
    // changes. body still reads forecast.hourly + lastUpdated, so observation stays intact and a
    // data change always invalidates the cache.
    @State private var snapshotCache = AtmosphereSnapshotCache()

    var body: some View {
        let overrides = (weather.debug && debugState?.overrideEnabled == true) ? debugState : nil
        let hasContent = weather.forecast.hourly != nil || overrides != nil
        let snapshot = overrides?.snapshot
            ?? (hasContent
                ? snapshotCache.snapshot(from: weather, at: location.coordinates)
                : .twilight)
        let moonPhase = overrides?.moonPhase ?? MoonPhase.phaseFraction()
        let cloudThickness = cloudThickness(for: snapshot)
        let cloudsVisible = snapshot.cloudDensity + snapshot.cloudCoverage > 0.02
        let pacing: SimulationPacing = reduceMotion ? .still : (isCoveredBySheet ? .background : .active)

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
                        StarsView(
                            pacing: pacing,
                            occlusionCenter: moonLayout.map {
                                CGPoint(
                                    x: proxy.size.width * $0.x,
                                    y: proxy.size.height * $0.y
                                )
                            },
                            occlusionRadius: MoonView.diameter / 2 + 8
                        )
                        .opacity(starOpacity)
                    }

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
                    }

                    if shouldShowSun(snapshot) {
                        SunView(progress: Double(snapshot.timeOfDay))
                            .opacity(Double((1 - snapshot.cloudDensity * 0.45) * snapshot.phase * snapshot.sunDiscVisibility))
                    }

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
                    .animation(.easeInOut(duration: 0.8), value: cloudThickness)
                    .animation(.easeInOut(duration: 0.8), value: cloudsVisible)

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
                    .animation(.easeInOut(duration: 1.2), value: fogVisible)

                    let stormVisible = shouldShowStorm(snapshot)
                    ZStack {
                        if stormVisible {
                            StormView(
                                type: stormContents(for: snapshot),
                                direction: stormDirection(for: snapshot),
                                strength: stormStrength(for: snapshot),
                                pacing: pacing
                            )
                            .id(String(describing: stormContents(for: snapshot)))
                            .transition(.opacity)
                            .opacity(reduceMotion ? 0.55 : 1)
                        }
                    }
                    .animation(.easeInOut(duration: 0.8), value: stormVisible)
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

                if weather.debug {
                    AtmosphereDebugOverlay(snapshot: snapshot)
                }
            }
            .preferredColorScheme(.dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AtmosphereSampler.skyGradient(snapshot: snapshot))
        }
        .ignoresSafeArea()
    }

    private func shouldShowSun(_ snapshot: AtmosphereSnapshot) -> Bool {
        snapshot.sunDiscVisibility > 0.01 && snapshot.cloudDensity < 0.82 && snapshot.precipitationIntensity < 0.55
    }

    private func shouldShowStorm(_ snapshot: AtmosphereSnapshot) -> Bool {
        // No minimum: any precipitation that exists gets drops on screen (0.001
        // only filters float dust). Light rates render sparse via stormStrength.
        max(snapshot.precipitationIntensity, snapshot.snowfallIntensity) > 0.001
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
        if weather.debug && !overriding {
            return 0.5
        }

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

    private func cloudThickness(for snapshot: AtmosphereSnapshot) -> Cloud.Thickness {
        switch snapshot.cloudCoverage {
        case ..<0.08:
            return .none
        case ..<0.25:
            return .thin
        case ..<0.45:
            return .light
        case ..<0.68:
            return .regular
        case ..<0.92:
            return .thick
        default:
            return .ultra
        }
    }

    private func stormContents(for snapshot: AtmosphereSnapshot) -> Storm.Contents {
        snapshot.condition == .snow ? .snow : .rain
    }

    private func stormDirection(for snapshot: AtmosphereSnapshot) -> Angle {
        let horizontalSlant = min(35, max(-35, Double(sin(snapshot.windDirection)) * Double(snapshot.windSpeed) * 55))
        return .degrees(horizontalSlant)
    }

    private func stormStrength(for snapshot: AtmosphereSnapshot) -> Int {
        let isSnow = snapshot.condition == .snow
        let intensity = isSnow ? snapshot.snowfallIntensity : snapshot.precipitationIntensity
        let base = Double(isSnow ? 90 : 45)
        // Ramp the base in over the first 0.05 of intensity (≈0.3 mm/h, the old
        // visibility threshold): drizzle gets a sparse handful of drops instead of
        // jumping straight to the full base count, and rates at or above the old
        // threshold look exactly as before.
        let ramp = min(1, Double(intensity) / 0.05)
        return max(12, min(220, Int(base * ramp + Double(intensity) * 170)))
    }
}

/// Memoizes `AtmosphereWeatherMapper.snapshot` so the same derived snapshot is reused across body
/// re-evaluations, recomputing only when the weather data (`lastUpdated`), location, or a coarse
/// 60-second time bucket changes. Held via `@State` (the @State-as-cache pattern) and only ever
/// touched on the main actor.
@MainActor
private final class AtmosphereSnapshotCache {
    private struct Key: Equatable {
        let lastUpdated: Date?
        let latitude: Double
        let longitude: Double
        let timeBucket: Int
    }

    private var key: Key?
    private var cached: AtmosphereSnapshot?

    func snapshot(from weather: Weather, at location: CLLocationCoordinate2D) -> AtmosphereSnapshot {
        let key = Key(
            lastUpdated: weather.lastUpdated,
            latitude: location.latitude,
            longitude: location.longitude,
            timeBucket: Int(Date.now.timeIntervalSince1970 / 60)
        )
        if key == self.key, let cached {
            return cached
        }

        let snapshot = AtmosphereWeatherMapper.snapshot(from: weather, at: location)
        self.key = key
        self.cached = snapshot
        return snapshot
    }
}

// Internal (not private): the onboarding scene dioramas reuse the same sky —
// including its lightning-flash timeline — with hand-built snapshots.
struct AtmosphereSkyShaderView: View {
    let snapshot: AtmosphereSnapshot
    let size: CGSize
    var moonGlow: Float = 0
    var pacing: SimulationPacing = .active

    var body: some View {
        // Lightning flashes need a live clock; any other sky is a static
        // frame that only changes with the snapshot.
        if snapshot.thunderIntensity > 0.05 {
            TimelineView(.animation(minimumInterval: pacing.minimumInterval(base: 1.0 / 20.0), paused: pacing.isPaused)) { timeline in
                sky(time: shaderTime(timeline.date.timeIntervalSinceReferenceDate))
            }
        } else {
            sky(time: shaderTime(snapshot.timestamp))
        }
    }

    private func sky(time: Float) -> some View {
        Rectangle().fill(skyShader(time: time))
    }

    /// Wraps the clock so it survives the trip into Float precision.
    private func shaderTime(_ seconds: Double) -> Float {
        Float(seconds.truncatingRemainder(dividingBy: 4096))
    }

    /// Mirrors SunView.sunX so the shader's glow lobe tracks the drawn sun.
    private var sunX: Float {
        (snapshot.timeOfDay - 0.3) * 1.8
    }

    private func skyShader(time: Float) -> Shader {
        Shader(
            function: ShaderFunction(library: .default, name: "atmosphereSky"),
            arguments: [
                .float2(Float(size.width), Float(size.height)),
                .float(time),
                .float(snapshot.sunElevation),
                .float(snapshot.cloudDensity),
                .float(snapshot.precipitationIntensity),
                .float(snapshot.snowfallIntensity),
                .float(snapshot.thunderIntensity),
                .float(snapshot.haze),
                .float(snapshot.turbidity),
                .float(sunX),
                .float(moonGlow)
            ]
        )
    }
}

/// Drifting ground-fog banks for the fog condition: an even haze plus three
/// soft bands swaying on detuned sine paths across the lower half.
private struct FogView: View {
    let density: Double
    let nightAmount: Double
    var pacing: SimulationPacing = .active

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let shade = 0.85 - 0.5 * nightAmount
            // Geometry is read once; only the sine sway needs the per-frame clock, so the
            // timeline drives the inner content rather than re-laying-out every tick.
            TimelineView(.animation(minimumInterval: pacing.minimumInterval(base: 1.0 / 20.0), paused: pacing.isPaused)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate

                ZStack {
                    // Even ground haze under the drifting banks.
                    LinearGradient(
                        colors: [.clear, Color(white: shade).opacity(0.30 * density)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: height * 0.5)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                    ForEach(0..<3, id: \.self) { band in
                        let phase = Double(band) * 2.1
                        let period = 38.0 + Double(band) * 11.0
                        let sway = sin(t * 2 * .pi / period + phase)

                        Ellipse()
                            .fill(Color(white: shade))
                            .frame(
                                width: width * 1.7,
                                height: height * (0.13 + 0.03 * Double(band))
                            )
                            .blur(radius: 30)
                            .opacity((0.16 + 0.07 * Double(band)) * density)
                            .position(
                                x: width * (0.5 + 0.22 * sway),
                                y: height * (0.58 + 0.14 * Double(band))
                            )
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

#Preview {
    WeatherSimulationView()
        .environment(Weather.mock)
        .environment(Location())
}
