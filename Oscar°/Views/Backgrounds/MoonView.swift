import SwiftUI

enum MoonPhase {
    static func phaseFraction(for date: Date = .now) -> Double {
        let synodicMonth = 29.530588853
        let knownNewMoon = 947_182_440.0
        let days = (date.timeIntervalSince1970 - knownNewMoon) / 86_400
        let fraction = (days / synodicMonth).truncatingRemainder(dividingBy: 1)
        return fraction >= 0 ? fraction : fraction + 1
    }

    static func illumination(for phase: Double) -> Double {
        (1 - cos(phase * 2 * .pi)) / 2
    }

    /// Fraction of the moon's pass across the sky — 0 at moonrise, 0.5 at
    /// transit, 1 at moonset — or nil while the moon is below the horizon.
    ///
    /// Equatorial approximation: the moon trails the sun by `phase` of a
    /// day, so it transits at local solar midnight shifted by the phase and
    /// is above the horizon for about half a day around that transit.
    /// (Declination shifts real rise/set by up to ±1–2 h at mid-latitudes.)
    static func altitudeProgress(timeOfDay: Double, phase: Double) -> Double? {
        let transit = (0.5 + phase).truncatingRemainder(dividingBy: 1)
        var offset = timeOfDay - transit
        offset -= offset.rounded()  // wrap to [-0.5, 0.5] days from transit
        guard abs(offset) <= 0.25 else { return nil }
        return offset * 2 + 0.5
    }
}

/// The sunlit region of the lunar disc as seen from Earth.
///
/// The lit region is bounded by the limb (a half circle on the lit side) and
/// the terminator, which projects onto the disc as a half-ellipse whose
/// horizontal semi-axis is `r·cos(2π·phase)` — toward the lit limb for a
/// crescent, away from it for a gibbous moon. Both halves are drawn with
/// cubic Béziers so the winding is unambiguous.
struct MoonLitShape: Shape {
    let phase: Double
    let litOnRight: Bool

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let kappa: CGFloat = 0.5522847498

        // +1 at new moon … −1 at full moon.
        let t = CGFloat(cos(phase * 2 * .pi))
        let side: CGFloat = litOnRight ? 1 : -1
        let limbX = side * r
        let bulge = side * t * r

        let top = CGPoint(x: c.x, y: c.y - r)
        let bottom = CGPoint(x: c.x, y: c.y + r)

        var path = Path()
        path.move(to: top)

        // Lit limb: half circle, top → bottom.
        path.addCurve(
            to: CGPoint(x: c.x + limbX, y: c.y),
            control1: CGPoint(x: c.x + limbX * kappa, y: c.y - r),
            control2: CGPoint(x: c.x + limbX, y: c.y - r * kappa)
        )
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: c.x + limbX, y: c.y + r * kappa),
            control2: CGPoint(x: c.x + limbX * kappa, y: c.y + r)
        )

        // Terminator: half ellipse, bottom → top.
        path.addCurve(
            to: CGPoint(x: c.x + bulge, y: c.y),
            control1: CGPoint(x: c.x + bulge * kappa, y: c.y + r),
            control2: CGPoint(x: c.x + bulge, y: c.y + r * kappa)
        )
        path.addCurve(
            to: top,
            control1: CGPoint(x: c.x + bulge, y: c.y - r * kappa),
            control2: CGPoint(x: c.x + bulge * kappa, y: c.y - r)
        )
        path.closeSubpath()
        return path
    }
}

struct MoonView: View {
    let phase: Double
    /// 0 at moonrise … 0.5 at transit … 1 at moonset.
    let altitudeProgress: Double
    /// Screen position as fractions of the container size.
    let xFraction: Double
    let yFraction: Double
    let isSouthernHemisphere: Bool
    /// 0 in full daylight … 1 at night. Suppresses the halo by day, where the
    /// real moon shows as a pale disc with no glow.
    var skyDarkness: Double = 1

    static let diameter: CGFloat = 68
    private static let glowTint = Color(red: 0.93, green: 0.95, blue: 1.0)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ZStack {
                    // Wide sky glow, emitted by the lit region only — a
                    // crescent throws a thin rim of light, a full moon a
                    // real halo.
                    litShape
                        .fill(Self.glowTint)
                        .blur(radius: 24 + 14 * illumination)
                        .opacity((0.50 + 0.45 * illumination) * skyDarkness)

                    // Tight glow hugging the lit limb.
                    litShape
                        .fill(.white)
                        .blur(radius: 6)
                        .opacity((0.60 + 0.30 * illumination) * skyDarkness)

                    // The disc occludes the sky glow behind it; without this
                    // the halo washes the dark side grey.
                    Circle()
                        .blendMode(.destinationOut)
                }
                .compositingGroup()

                // Dark side: a touch darker than the sky, never a hard disc.
                // (Stars behind the moon are culled in StarsView.)
                Circle()
                    .fill(.black.opacity(0.26))

                // Earthshine: the dark side is only barely visible against
                // the night sky.
                moonPhoto
                    .opacity(0.02)

                // Sunlit surface: soft terminator, crisp limb.
                moonPhoto
                    .brightness(0.50)
                    .contrast(1.10)
                    .saturation(0.9)
                    .mask {
                        litShape
                            .fill(.white)
                            .blur(radius: 1.6)
                            .clipShape(Circle())
                    }

                // Inner bloom: lifts the lit surface's luminance like an
                // overexposed photo while the crater texture still shows.
                litShape
                    .fill(.white)
                    .blur(radius: 4)
                    .opacity(0.30)
                    .clipShape(Circle())
            }
            .frame(width: Self.diameter, height: Self.diameter)
            // The lit limb leans toward the below-horizon sun.
            .rotationEffect(.degrees(litOnRight ? 24 : -24))
            // Atmospheric extinction: subtly dimmer near rise and set.
            .opacity(0.9 + 0.15 * sin(.pi * altitudeProgress))
            .position(
                x: proxy.size.width * xFraction,
                y: proxy.size.height * yFraction
            )
        }
        .allowsHitTesting(false)
    }

    private var illumination: Double {
        MoonPhase.illumination(for: phase)
    }

    // Northern hemisphere: a waxing moon is lit on the right; mirrored south
    // of the equator.
    private var litOnRight: Bool {
        (phase < 0.5) != isSouthernHemisphere
    }

    private var litShape: MoonLitShape {
        MoonLitShape(phase: phase, litOnRight: litOnRight)
    }

    private var moonPhoto: some View {
        Image("moon")
            .resizable()
            .scaledToFit()
            .clipShape(Circle())
    }
}

#Preview("Phases") {
    ZStack {
        Color(red: 0.08, green: 0.09, blue: 0.18).ignoresSafeArea()
        VStack(spacing: 0) {
            ForEach([0.08, 0.25, 0.4, 0.5, 0.6, 0.75, 0.83], id: \.self) { phase in
                MoonView(
                    phase: phase,
                    altitudeProgress: 0.5,
                    xFraction: 0.5,
                    yFraction: 0.5,
                    isSouthernHemisphere: false
                )
                .frame(height: 110)
            }
        }
    }
}
