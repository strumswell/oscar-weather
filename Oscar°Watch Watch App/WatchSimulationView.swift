//
//  WatchSimulationView.swift
//  Oscar°Watch Watch App
//
//  Watch-tuned port of the iPhone weather simulation: the shared atmosphere
//  snapshot drives a gradient sky (no Metal shader here) with the shared
//  star/moon/sun/cloud/rain layers at the reduced background frame rate.
//

import CoreLocation
import SwiftUI

struct WatchSimulationView: View {
    enum Style {
        /// Full animated scene, for the Now page.
        case full
        /// Sky gradient only, dimmed so text on content pages stays legible.
        case gradientOnly
    }

    var style: Style = .full
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @State private var snapshotCache = WatchAtmosphereSnapshotCache()

    private static let moonDiameter: CGFloat = 34

    var body: some View {
        let hasContent = weather.forecast.hourly != nil
        let snapshot = hasContent
            ? snapshotCache.snapshot(from: weather, at: location.coordinates)
            : .twilight

        switch style {
        case .gradientOnly:
            Rectangle()
                .fill(AtmosphereSampler.skyGradient(snapshot: snapshot))
                .overlay(Color.black.opacity(0.35))
                .ignoresSafeArea()
        case .full:
            fullScene(snapshot: snapshot)
        }
    }

    private func fullScene(snapshot: AtmosphereSnapshot) -> some View {
        // Always-on wrist-down state must not burn frames on particles. Ambient
        // layers (stars, clouds) drift slowly and get by at 8 fps; falling rain
        // and snow judder visibly there, so the storm runs at full rate.
        let isStill = reduceMotion || luminanceReduced
        let pacing: SimulationPacing = isStill ? .still : .background
        let stormPacing: SimulationPacing = isStill ? .still : .active
        let moonPhase = MoonPhase.phaseFraction()
        let cloudsVisible = snapshot.cloudDensity + snapshot.cloudCoverage > 0.02

        return GeometryReader { proxy in
            ZStack {
                let moonProgress = moonAltitudeProgress(snapshot, phase: moonPhase)
                let moonLayout = moonProgress.map { progress in
                    (
                        x: 0.12 + 0.76 * progress,
                        y: 0.30 - 0.12 * sin(.pi * progress)
                    )
                }
                let moonGlow = moonProgress.map {
                    Float(MoonPhase.illumination(for: moonPhase))
                        * snapshot.nightAmount
                        * Float(sin(.pi * $0))
                } ?? 0

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
                        occlusionRadius: Self.moonDiameter / 2 + 6
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
                        skyDarkness: Double(snapshot.nightAmount),
                        diameter: Self.moonDiameter
                    )
                    .opacity(
                        Double(0.35 + 0.65 * snapshot.nightAmount)
                            * Double(1 - snapshot.cloudDensity * 0.4)
                    )
                    .blur(radius: CGFloat(snapshot.cloudDensity) * 2)
                }

                if shouldShowSun(snapshot) {
                    SunView(progress: Double(snapshot.timeOfDay))
                        .opacity(Double((1 - snapshot.cloudDensity * 0.45) * snapshot.phase))
                }

                if cloudsVisible {
                    CloudsView(
                        thickness: cloudThickness(for: snapshot),
                        topTint: AtmosphereSampler.cloudTopTint(snapshot: snapshot, moonGlow: moonGlow),
                        bottomTint: AtmosphereSampler.cloudBottomTint(snapshot: snapshot, moonGlow: moonGlow),
                        pacing: pacing
                    )
                    .opacity(Double(min(1, snapshot.cloudDensity + snapshot.cloudCoverage * 0.25)))
                }

                if shouldShowStorm(snapshot) {
                    StormView(
                        type: snapshot.condition == .snow ? .snow : .rain,
                        direction: stormDirection(for: snapshot),
                        strength: stormStrength(for: snapshot),
                        pacing: stormPacing
                    )
                    .opacity(reduceMotion ? 0.55 : 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AtmosphereSampler.skyGradient(snapshot: snapshot))
        }
        .ignoresSafeArea()
    }

    private func shouldShowSun(_ snapshot: AtmosphereSnapshot) -> Bool {
        snapshot.phase > 0.08 && snapshot.cloudDensity < 0.82 && snapshot.precipitationIntensity < 0.55
    }

    private func shouldShowStorm(_ snapshot: AtmosphereSnapshot) -> Bool {
        max(snapshot.precipitationIntensity, snapshot.snowfallIntensity) > 0.001
    }

    private func moonAltitudeProgress(_ snapshot: AtmosphereSnapshot, phase: Double) -> Double? {
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

    private func stormDirection(for snapshot: AtmosphereSnapshot) -> Angle {
        let horizontalSlant = min(35, max(-35, Double(sin(snapshot.windDirection)) * Double(snapshot.windSpeed) * 55))
        return .degrees(horizontalSlant)
    }

    /// Half the iPhone's particle counts: the canvas is a fraction of the size
    /// and every drop costs battery here.
    private func stormStrength(for snapshot: AtmosphereSnapshot) -> Int {
        let isSnow = snapshot.condition == .snow
        let intensity = isSnow ? snapshot.snowfallIntensity : snapshot.precipitationIntensity
        let base = Double(isSnow ? 45 : 22)
        let ramp = min(1, Double(intensity) / 0.05)
        return max(8, min(110, Int(base * ramp + Double(intensity) * 85)))
    }
}

/// Same @State-as-cache pattern as the iPhone simulation: reuse the derived
/// snapshot across body re-evaluations, recomputing only when the weather
/// data, location, or a coarse 60-second time bucket changes.
@MainActor
private final class WatchAtmosphereSnapshotCache {
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

#Preview {
    WatchSimulationView()
        .environment(Weather.mock)
        .environment(Location())
}
