import SwiftUI

/// Scene decisions every simulation shares (phone, watch, location cards).
extension AtmosphereSnapshot {
    var cloudThickness: Cloud.Thickness {
        switch cloudCoverage {
        case ..<0.08: .none
        case ..<0.25: .thin
        case ..<0.45: .light
        case ..<0.68: .regular
        case ..<0.92: .thick
        default: .ultra
        }
    }

    var showsSunDisc: Bool {
        sunDiscVisibility > 0.01 && cloudDensity < 0.82 && precipitationIntensity < 0.55
    }

    /// Any precipitation gets drops on screen; 0.001 only filters float dust.
    var showsPrecipitation: Bool {
        max(precipitationIntensity, snowfallIntensity) > 0.001
    }

    var stormContents: Storm.Contents {
        condition == .snow ? .snow : .rain
    }

    var stormSlant: Angle {
        .degrees(min(35, max(-35, Double(sin(windDirection)) * Double(windSpeed) * 55)))
    }

    /// Particle count for the storm layer. With `ramped`, the base fades in over
    /// the first 0.05 of intensity so drizzle gets a sparse handful of drops.
    func stormStrength(rainBase: Double, snowBase: Double, weight: Double, floor: Int, cap: Int, ramped: Bool = true) -> Int {
        let isSnow = condition == .snow
        let intensity = Double(isSnow ? snowfallIntensity : precipitationIntensity)
        let base = isSnow ? snowBase : rainBase
        let ramp = ramped ? min(1, intensity / 0.05) : 1
        return max(floor, min(cap, Int(base * ramp + intensity * weight)))
    }
}
