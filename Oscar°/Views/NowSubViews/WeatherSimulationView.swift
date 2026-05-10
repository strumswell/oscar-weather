//
//  WeatherSimulationView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 02.01.24.
//

import CoreLocation
import SwiftUI

struct WeatherSimulationView: View {
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let snapshot = AtmosphereWeatherMapper.snapshot(from: weather, at: location.coordinates)

        GeometryReader { proxy in
            ZStack {
                if !weather.isLoading && weather.forecast.hourly != nil {
                    AtmosphereSkyShaderView(
                        snapshot: snapshot,
                        size: proxy.size
                    )

                    StarsView()
                        .opacity(Double(snapshot.nightAmount) * Double(1 - snapshot.cloudCoverage * 0.85))

                    if shouldShowSun(snapshot) {
                        SunView(progress: Double(snapshot.timeOfDay))
                            .opacity(Double((1 - snapshot.cloudDensity * 0.45) * snapshot.phase))
                    }

                    CloudsView(
                        thickness: cloudThickness(for: snapshot),
                        topTint: AtmosphereSampler.cloudTopTint(snapshot: snapshot),
                        bottomTint: AtmosphereSampler.cloudBottomTint(snapshot: snapshot)
                    )
                    .id(String(describing: cloudThickness(for: snapshot)))
                    .opacity(Double(min(1, snapshot.cloudDensity + snapshot.cloudCoverage * 0.25)))

                    if shouldShowStorm(snapshot) {
                        StormView(
                            type: stormContents(for: snapshot),
                            direction: stormDirection(for: snapshot),
                            strength: stormStrength(for: snapshot)
                        )
                        .id(String(describing: stormContents(for: snapshot)))
                        .opacity(reduceMotion ? 0.55 : 1)
                    }
                } else {
                    AtmosphereSampler.skyGradient(snapshot: .fallback)
                }

                if weather.debug {
                    debugOverlay(snapshot: snapshot)
                }
            }
            .preferredColorScheme(.dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AtmosphereSampler.skyGradient(snapshot: snapshot))
        }
        .ignoresSafeArea()
    }

    private func debugOverlay(snapshot: AtmosphereSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Atmosphere")
                .font(.caption.bold())
            Text("Condition: \(String(describing: snapshot.condition))")
            Text("Cloud: \(snapshot.cloudCoverage, specifier: "%.2f") / \(snapshot.cloudDensity, specifier: "%.2f")")
            Text("Precip: \(snapshot.precipitationAmount, specifier: "%.2f") mm / \(snapshot.precipitationIntensity, specifier: "%.2f")")
            Text("Snow: \(snapshot.snowfallAmount, specifier: "%.2f") mm / \(snapshot.snowfallIntensity, specifier: "%.2f")")
            Text("Haze: \(snapshot.haze, specifier: "%.2f") Turbidity: \(snapshot.turbidity, specifier: "%.2f")")
            Text("Sun: \(snapshot.sunElevation * 180 / .pi, specifier: "%.1f")°")
            Text(weather.isLoading.description)
            if !weather.loadingQueries.isEmpty {
                Text(weather.loadingQueries.sorted().map(\.displayName).joined(separator: ", "))
            }
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 64)
        .padding(.horizontal, 12)
    }

    private func shouldShowSun(_ snapshot: AtmosphereSnapshot) -> Bool {
        snapshot.phase > 0.08 && snapshot.cloudDensity < 0.82 && snapshot.precipitationIntensity < 0.55
    }

    private func shouldShowStorm(_ snapshot: AtmosphereSnapshot) -> Bool {
        max(snapshot.precipitationIntensity, snapshot.snowfallIntensity) > 0.05
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
        let base = isSnow ? 90 : 45
        return max(12, min(220, Int(Double(base) + Double(intensity) * 170)))
    }
}

private struct AtmosphereSkyShaderView: View {
    let snapshot: AtmosphereSnapshot
    let size: CGSize

    var body: some View {
        Rectangle()
            .fill(skyShader(seed: Float(snapshot.timestamp)))
    }

    private func skyShader(seed: Float) -> Shader {
        Shader(
            function: ShaderFunction(library: .default, name: "atmosphereSky"),
            arguments: [
                .float2(Float(size.width), Float(size.height)),
                .float(seed),
                .float(snapshot.sunElevation),
                .float(snapshot.phase),
                .float(snapshot.cloudDensity),
                .float(snapshot.precipitationIntensity),
                .float(snapshot.snowfallIntensity),
                .float(snapshot.thunderIntensity),
                .float(snapshot.haze),
                .float(snapshot.turbidity)
            ]
        )
    }
}

#Preview {
    WeatherSimulationView()
        .environment(Weather.mock)
        .environment(Location())
}
