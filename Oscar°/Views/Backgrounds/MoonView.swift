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

    /// Fraction of the moon's pass across the sky — 0 at moonrise, 0.5 at transit, 1 at
    /// moonset — or nil while the moon is below the horizon.
    ///
    /// Uses a low-precision lunar ephemeris and the observer's latitude/longitude, so rise
    /// and set track the real times (within a few minutes). A phase-only approximation can be
    /// hours off at mid-latitudes because it ignores the moon's declination.
    static func skyProgress(date: Date, latitude: Double, longitude: Double) -> Double? {
        let observed = observation(date: date, latitude: latitude, longitude: longitude)
        guard observed.altitude > 0 else { return nil }

        // Hour angle at rise/set (the semi-diurnal arc). |cos| > 1 ⇒ circumpolar (never sets)
        // at this latitude/declination — the moon is up, so place it purely by hour angle.
        let cosSemiArc = -tan(latitude * .pi / 180) * tan(observed.declination)
        guard abs(cosSemiArc) <= 1 else {
            return min(max(observed.hourAngle / (2 * .pi) + 0.5, 0), 1)
        }
        let semiArc = acos(cosSemiArc)
        return min(max(observed.hourAngle / (2 * semiArc) + 0.5, 0), 1)
    }

    /// The next moonrise and moonset after `date` for the given location (each searched up
    /// to ~26 h ahead; either can be nil on a day the moon doesn't rise or set).
    static func riseAndSet(after date: Date, latitude: Double, longitude: Double) -> (rise: Date?, set: Date?) {
        func altitude(_ t: Double) -> Double {
            observation(date: Date(timeIntervalSince1970: t), latitude: latitude, longitude: longitude).altitude
        }
        let start = date.timeIntervalSince1970
        let end = start + 26 * 3600
        let coarseStep = 300.0
        var rise: Date?
        var set: Date?
        var t0 = start
        var a0 = altitude(t0)
        while t0 < end, rise == nil || set == nil {
            let t1 = t0 + coarseStep
            let a1 = altitude(t1)
            if rise == nil, a0 < 0, a1 >= 0 {
                rise = Date(timeIntervalSince1970: refineCrossing(t0, t1, rising: true, altitude: altitude))
            }
            if set == nil, a0 > 0, a1 <= 0 {
                set = Date(timeIntervalSince1970: refineCrossing(t0, t1, rising: false, altitude: altitude))
            }
            t0 = t1
            a0 = a1
        }
        return (rise, set)
    }

    /// A human-readable phase name for a phase fraction (0 = new, 0.5 = full).
    static func name(for phase: Double) -> String {
        let p = (phase.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        switch p {
        case ..<0.02, 0.98...: return "New Moon"
        case ..<0.23: return "Waxing Crescent"
        case ..<0.27: return "First Quarter"
        case ..<0.48: return "Waxing Gibbous"
        case ..<0.52: return "Full Moon"
        case ..<0.73: return "Waning Gibbous"
        case ..<0.77: return "Last Quarter"
        default: return "Waning Crescent"
        }
    }

    /// Bisects a bracketed horizon crossing to ~second precision.
    private static func refineCrossing(_ lo: Double, _ hi: Double, rising: Bool, altitude: (Double) -> Double) -> Double {
        var lo = lo, hi = hi
        for _ in 0..<18 {
            let mid = (lo + hi) / 2
            if (altitude(mid) >= 0) == rising { hi = mid } else { lo = mid }
        }
        return (lo + hi) / 2
    }

    /// Local horizontal coordinates of the moon at `date`: altitude, hour angle, declination
    /// (all radians).
    private static func observation(date: Date, latitude: Double, longitude: Double) -> (altitude: Double, hourAngle: Double, declination: Double) {
        let phi = latitude * .pi / 180
        let (rightAscension, declination) = equatorialPosition(date: date)
        let localSiderealTime = greenwichMeanSiderealTime(date: date) + longitude * .pi / 180
        let hourAngle = atan2(sin(localSiderealTime - rightAscension), cos(localSiderealTime - rightAscension))
        let altitude = asin(sin(phi) * sin(declination) + cos(phi) * cos(declination) * cos(hourAngle))
        return (altitude, hourAngle, declination)
    }

    /// Geocentric equatorial position (right ascension, declination) of the moon, in radians.
    /// Low-precision (~0.1–0.2°) truncation of the standard lunar series — accurate enough for
    /// rise/set timing to a few minutes.
    private static func equatorialPosition(date: Date) -> (rightAscension: Double, declination: Double) {
        let rad = Double.pi / 180
        let d = julianDaysSinceJ2000(date)

        let meanLongitude = 218.316 + 13.176396 * d
        let meanAnomaly = (134.963 + 13.064993 * d) * rad
        let argLatitude = (93.272 + 13.229350 * d) * rad
        let elongation = (297.850 + 12.190749 * d) * rad
        let sunAnomaly = (357.529 + 0.985600 * d) * rad

        let longitude = (meanLongitude
            + 6.289 * sin(meanAnomaly)
            + 1.274 * sin(2 * elongation - meanAnomaly)
            + 0.658 * sin(2 * elongation)
            + 0.214 * sin(2 * meanAnomaly)
            - 0.186 * sin(sunAnomaly)
            - 0.114 * sin(2 * argLatitude)) * rad
        let latitude = (5.128 * sin(argLatitude)
            + 0.281 * sin(meanAnomaly + argLatitude)
            - 0.278 * sin(argLatitude - meanAnomaly)
            - 0.173 * sin(2 * elongation - argLatitude)) * rad

        let obliquity = 23.4393 * rad
        let rightAscension = atan2(
            sin(longitude) * cos(obliquity) - tan(latitude) * sin(obliquity),
            cos(longitude)
        )
        let declination = asin(
            sin(latitude) * cos(obliquity) + cos(latitude) * sin(obliquity) * sin(longitude)
        )
        return (rightAscension, declination)
    }

    /// Greenwich Mean Sidereal Time at `date`, in radians (IAU 1982).
    private static func greenwichMeanSiderealTime(date: Date) -> Double {
        let d = julianDaysSinceJ2000(date)
        let degrees = (280.46061837 + 360.98564736629 * d).truncatingRemainder(dividingBy: 360)
        return degrees * Double.pi / 180
    }

    /// Days (including fraction) since the J2000.0 epoch, 2000-01-01 12:00 UTC.
    private static func julianDaysSinceJ2000(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 - 10_957.5
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
