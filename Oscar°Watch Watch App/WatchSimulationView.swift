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
    @State private var snapshotCache = AtmosphereSnapshotCache()

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
                        MoonPhase.skyVisibility(phase: moonPhase, nightAmount: Double(snapshot.nightAmount))
                            * Double(1 - snapshot.cloudDensity * 0.4)
                    )
                    .blur(radius: CGFloat(snapshot.cloudDensity) * 2)
                }

                if snapshot.showsSunDisc {
                    SunView(progress: Double(snapshot.timeOfDay))
                        .opacity(Double((1 - snapshot.cloudDensity * 0.45) * snapshot.phase * snapshot.sunDiscVisibility))
                }

                if cloudsVisible {
                    CloudsView(
                        thickness: snapshot.cloudThickness,
                        topTint: AtmosphereSampler.cloudTopTint(snapshot: snapshot, moonGlow: moonGlow),
                        bottomTint: AtmosphereSampler.cloudBottomTint(snapshot: snapshot, moonGlow: moonGlow),
                        pacing: pacing
                    )
                    .opacity(Double(min(1, snapshot.cloudDensity + snapshot.cloudCoverage * 0.25)))
                }

                if snapshot.showsPrecipitation {
                    StormView(
                        type: snapshot.condition == .snow ? .snow : .rain,
                        direction: snapshot.stormSlant,
                        strength: snapshot.stormStrength(rainBase: 22, snowBase: 45, weight: 85, floor: 8, cap: 110),
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

}

#Preview {
    WatchSimulationView()
        .environment(Weather.mock)
        .environment(Location())
}
