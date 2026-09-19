import SwiftUI

/// Scene decisions every simulation shares (phone, watch, location cards).
extension AtmosphereSnapshot {
    var cloudDeck: CloudDeck {
        cloudLow + cloudMid + cloudHigh > 0
            ? CloudDeck(low: cloudLow, mid: cloudMid, high: cloudHigh)
            : CloudDeck(total: cloudCoverage)
    }

    /// Screen drift of the low deck in points per second at sprite scale 1,
    /// signed like the storm slant (wind from the east blows left). Calm air
    /// still drifts a little so the sky never freezes.
    var cloudDrift: Double {
        let along = Double(sin(windDirection))
        let speed = 3 + 9 * Double(windSpeed)
        return (along >= 0 ? -1 : 1) * speed * (0.5 + 0.5 * abs(along))
    }

    /// Unit vector from the sun (SunView's x mapping, y ≈ 0.08 of the screen)
    /// toward the deck centre, in screen fractions: the lit edge of every
    /// sprite faces the sun. nil below the horizon — plain top-down shading.
    var cloudLightDirection: CGVector? {
        guard sunDiscVisibility > 0.01 else { return nil }
        let dx = 0.5 - (Double(timeOfDay) - 0.3) * 1.8
        let dy = 0.35 - 0.08
        let length = (dx * dx + dy * dy).squareRoot()
        return CGVector(dx: dx / length, dy: dy / length)
    }

    /// Cloud between viewer and moon, weighted by optical thickness per band:
    /// a cirrus veil barely dims the disc, a low deck hides it.
    var moonVeil: Float {
        let deck = cloudDeck
        return min(1, deck.high * 0.35 + deck.mid * 0.6 + deck.low)
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
