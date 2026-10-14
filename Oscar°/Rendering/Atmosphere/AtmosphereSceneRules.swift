import SwiftUI

extension AtmosphereSnapshot {
    var cloudDeck: CloudDeck {
        cloudLow + cloudMid + cloudHigh > 0
            ? CloudDeck(low: cloudLow, mid: cloudMid, high: cloudHigh)
            : CloudDeck(total: cloudCoverage)
    }

    var cloudDrift: Double {
        let along = Double(sin(windDirection))
        let speed = 3 + 9 * Double(windSpeed)
        return (along >= 0 ? -1 : 1) * speed * (0.5 + 0.5 * abs(along))
    }

    var cloudLightDirection: CGVector? {
        guard sunDiscVisibility > 0.01 else { return nil }
        let dx = 0.5 - (Double(timeOfDay) - 0.3) * 1.8
        let dy = 0.35 - 0.08
        let length = (dx * dx + dy * dy).squareRoot()
        return CGVector(dx: dx / length, dy: dy / length)
    }

    var moonVeil: Float {
        let deck = cloudDeck
        return min(1, deck.high * 0.35 + deck.mid * 0.6 + deck.low)
    }

    var showsSunDisc: Bool {
        sunDiscVisibility > 0.01 && cloudDensity < 0.82 && precipitationIntensity < 0.55
    }

    var showsPrecipitation: Bool {
        max(precipitationIntensity, snowfallIntensity) > 0.001
    }

    var stormContents: Storm.Contents {
        condition == .snow ? .snow : .rain
    }

    var stormSlant: Angle {
        .degrees(min(35, max(-35, Double(sin(windDirection)) * Double(windSpeed) * 55)))
    }

    func stormStrength(rainBase: Double, snowBase: Double, weight: Double, floor: Int, cap: Int, ramped: Bool = true) -> Int {
        let isSnow = condition == .snow
        let intensity = Double(isSnow ? snowfallIntensity : precipitationIntensity)
        let base = isSnow ? snowBase : rainBase
        let ramp = ramped ? min(1, intensity / 0.05) : 1
        return max(floor, min(cap, Int(base * ramp + intensity * weight)))
    }
}
