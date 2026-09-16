//
//  AtmosphereDebugOverlay.swift
//  Oscar°
//
//  Read-only stats overlay shown in debug mode, reflecting whichever
//  snapshot (live or overridden) the simulation is currently rendering.
//

import SwiftUI

struct AtmosphereDebugOverlay: View {
    let snapshot: AtmosphereSnapshot
    @Environment(Weather.self) private var weather: Weather

    var body: some View {
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
}
