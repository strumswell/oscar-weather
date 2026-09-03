import simd
import SwiftUI

enum AtmosphereSampler {
    static func skyGradient(snapshot: AtmosphereSnapshot, sampleCount: Int = 8) -> LinearGradient {
        LinearGradient(
            stops: skyStops(snapshot: snapshot, sampleCount: sampleCount),
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func skyStops(snapshot: AtmosphereSnapshot, sampleCount: Int = 8) -> [Gradient.Stop] {
        let count = max(2, sampleCount)
        return (0..<count).map { index in
            let location = Float(index) / Float(count - 1)
            return Gradient.Stop(
                color: color(for: snapshot, horizonFactor: location),
                location: Double(location)
            )
        }
    }

    /// Card wash for the Now stack, laid over the faded frosted material.
    /// In high sun it carries a darkened, saturation-pushed sample of the sky
    /// — the material's frost desaturates whatever shows through it, so a
    /// neutral layer always reads gray over a blue day; the wash has to put
    /// the hue back. Toward sunset the wash fades out entirely (bare glass
    /// reads well in every dim scene), which is also what retires the old
    /// scroll mismatch: cards never wear the horizon's warm band. At night it
    /// flips to a faint white lift so cards separate from a near-black sky.
    static func cardFill(snapshot: AtmosphereSnapshot) -> Color {
        let elevationDegrees = snapshot.sunElevation * 180 / .pi
        let daylight = smoothstep(3, 14, elevationDegrees)
        // High sun samples the lower third of the sky (the zenith overshot
        // into navy); as the sun drops the sample slides UP toward the
        // zenith, away from the warming horizon, so the residual hue stays
        // cool while the wash fades.
        let sampleHeight = 0.3 + 0.37 * daylight
        var base = skyVector(for: snapshot, horizonFactor: sampleHeight)
        let level = luminance(base)
        // Push the sample off its gray axis so the hue survives the frost —
        // hard, because the material desaturates everything behind it and the
        // wash has to make up the difference — then darken so the white text
        // keeps its contrast under bright sky.
        let gray = simd_float3(repeating: level)
        base = gray + (base - gray) * 2.1
        base *= 0.62
        base = simd_clamp(base, simd_float3(repeating: 0), simd_float3(repeating: 1))
        // Both ramps meet near zero in twilight, so the flip from the fading
        // day wash to the night lift is invisible.
        let dayOpacity = 0.55 * daylight
        let lift = 0.12 * (1 - smoothstep(0.02, 0.16, level))
        return dayOpacity >= lift
            ? Color(
                red: Double(base.x),
                green: Double(base.y),
                blue: Double(base.z)
            ).opacity(Double(dayOpacity))
            : Color.white.opacity(Double(lift))
    }

    /// Strength of the white card hairline: the daytime 0.15 reads too hot
    /// against a dark night sky, so it eases down as night falls.
    static func cardBorderOpacity(snapshot: AtmosphereSnapshot) -> Double {
        0.15 - 0.07 * Double(snapshot.nightAmount)
    }

    static func cloudTopTint(snapshot: AtmosphereSnapshot, moonGlow: Float = 0) -> Color {
        cloudColor(snapshot: snapshot, top: true, moonGlow: moonGlow)
    }

    static func cloudBottomTint(snapshot: AtmosphereSnapshot, moonGlow: Float = 0) -> Color {
        cloudColor(snapshot: snapshot, top: false, moonGlow: moonGlow)
    }

    private static func color(for snapshot: AtmosphereSnapshot, horizonFactor: Float) -> Color {
        rgbColor(skyVector(for: snapshot, horizonFactor: horizonFactor))
    }

    /// Sky color in linear RGB, kept as a vector so the cloud and card math
    /// never round-trips through UIColor.
    private static func skyVector(for snapshot: AtmosphereSnapshot, horizonFactor: Float) -> simd_float3 {
        let dayZenith = simd_float3(0.20, 0.48, 0.86)
        let dayHorizon = simd_float3(0.68, 0.84, 0.95)
        let goldenZenith = simd_float3(0.38, 0.56, 0.84)
        let goldenHorizon = simd_float3(0.98, 0.66, 0.48)
        let twilightZenith = simd_float3(0.06, 0.11, 0.28)
        // Blue hour: deep cobalt, not warm plum (ozone Chappuis absorption).
        let twilightHorizon = simd_float3(0.14, 0.26, 0.52)
        let nightZenith = simd_float3(0.022, 0.040, 0.095)
        let nightHorizon = simd_float3(0.042, 0.052, 0.11)

        let h = smoothstep(0, 1, horizonFactor)
        let day = mix(dayZenith, dayHorizon, t: h)
        let golden = mix(goldenZenith, goldenHorizon, t: h * 0.92)
        let twilight = mix(twilightZenith, twilightHorizon, t: h * 0.60)
        let night = mix(nightZenith, nightHorizon, t: h)

        let elevationDegrees = snapshot.sunElevation * 180 / .pi
        var color: simd_float3
        if elevationDegrees >= 6 {
            color = day
        } else if elevationDegrees >= 0 {
            color = mix(golden, day, t: smoothstep(0, 6, elevationDegrees))
        } else if elevationDegrees >= -6 {
            color = mix(twilight, golden, t: smoothstep(-4, 0, elevationDegrees))
        } else {
            color = mix(night, twilight, t: smoothstep(-16, -6, elevationDegrees))
        }

        let gray = simd_float3(repeating: (color.x + color.y + color.z) / 3)
        color = mix(color, gray, t: snapshot.cloudDensity * 0.38 + snapshot.haze * 0.22)
        color *= 1 - snapshot.precipitationIntensity * 0.36 - snapshot.thunderIntensity * 0.30
        color += simd_float3(0.02, 0.025, 0.035) * snapshot.haze
        if snapshot.snowfallIntensity > 0 {
            color = mix(color, simd_float3(0.72, 0.78, 0.84), t: snapshot.snowfallIntensity * 0.18)
        }

        return clamp(color)
    }

    private static func cloudColor(snapshot: AtmosphereSnapshot, top: Bool, moonGlow: Float) -> Color {
        let base = skyVector(for: snapshot, horizonFactor: top ? 0.32 : 0.62)
        // Bright-moon nights dim the clouds less ("silver lining").
        let nightDim = 1 - snapshot.nightAmount * (0.7 - 0.25 * moonGlow)
        let bright = (top ? simd_float3(0.92, 0.92, 0.90) : simd_float3(0.54, 0.56, 0.60)) * nightDim
        var storm = (top ? simd_float3(0.42, 0.44, 0.48) : simd_float3(0.15, 0.16, 0.20)) * nightDim
        // Severe storms drift toward teal — the real "green sky" of
        // hail-heavy cells. It's a daytime phenomenon, shows mainly in the
        // bright cloud body, and ordinary thunderstorms stay grey
        // (thunderIntensity floors at 0.55 for any thunderstorm code).
        let severity = max(0, (snapshot.thunderIntensity - 0.55) / 0.45)
        let stormDaylight = 1 - snapshot.nightAmount
        let tealStrength = severity * stormDaylight * (top ? 0.5 : 0.15)
        storm = mix(storm, simd_float3(0.28, 0.40, 0.42) * nightDim, t: tealStrength)
        let rain = mix(bright, storm, t: max(snapshot.precipitationIntensity, snapshot.thunderIntensity))
        var cloud = mix(bright, rain, t: snapshot.cloudDensity)

        let elevDeg = snapshot.sunElevation * 180 / .pi
        let sunsetProximity = 1 - min(1, abs(min(max(elevDeg, -6), 6)) / 6)
        // Golden hour lights clouds from below: warm bottoms, cool blue-grey
        // tops. Heavy decks block the low sun, so the effect fades with
        // density and rain.
        let underlight = sunsetProximity * (1 - max(snapshot.precipitationIntensity, snapshot.cloudDensity * 0.7))
        if top {
            cloud = mix(cloud, simd_float3(0.46, 0.48, 0.62), t: underlight * 0.40)
        } else {
            cloud = mix(cloud, simd_float3(0.99, 0.62, 0.40), t: underlight * 0.65)
        }

        // Less sky-mixing at sunset than before, so the warm light survives.
        let tintFactor = 0.28 + snapshot.nightAmount * 0.4 + sunsetProximity * 0.12
        var result = mix(cloud, base, t: tintFactor)

        // Never let the cloud melt into the sky behind it.
        let sky = skyVector(for: snapshot, horizonFactor: 0.45)
        let separation: Float = 0.06
        let difference = luminance(result) - luminance(sky)
        if abs(difference) < separation {
            let direction: Float = difference >= 0 ? 1 : -1
            result += simd_float3(repeating: direction * (separation - abs(difference)))
        }

        return rgbColor(clamp(result))
    }

    private static func luminance(_ color: simd_float3) -> Float {
        color.x * 0.299 + color.y * 0.587 + color.z * 0.114
    }

    private static func rgbColor(_ vector: simd_float3) -> Color {
        Color(red: Double(vector.x), green: Double(vector.y), blue: Double(vector.z))
    }

    private static func mix(_ lhs: simd_float3, _ rhs: simd_float3, t: Float) -> simd_float3 {
        simd_mix(lhs, rhs, simd_float3(repeating: min(max(t, 0), 1)))
    }

    private static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let x = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return x * x * (3 - 2 * x)
    }

    private static func clamp(_ vector: simd_float3) -> simd_float3 {
        simd_clamp(vector, simd_float3(repeating: 0), simd_float3(repeating: 1))
    }
}
