import Foundation

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

    static func skyVisibility(phase: Double, nightAmount: Double, daytimeCeiling: Double = 0.5) -> Double {
        let separation = 180 - abs(180 - 360 * phase)
        let elongation = smoothstep(28, 65, separation)
        let lit = smoothstep(0.08, 0.42, illumination(for: phase))
        let daytimeVisibility = elongation * lit
        return daytimeCeiling * daytimeVisibility * (1 - nightAmount) + nightAmount
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        let t = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func skyProgress(date: Date, latitude: Double, longitude: Double) -> Double? {
        let observed = observation(date: date, latitude: latitude, longitude: longitude)
        guard observed.altitude > 0 else { return nil }

        let cosSemiArc = -tan(latitude * .pi / 180) * tan(observed.declination)
        guard abs(cosSemiArc) <= 1 else {
            return min(max(observed.hourAngle / (2 * .pi) + 0.5, 0), 1)
        }
        let semiArc = acos(cosSemiArc)
        return min(max(observed.hourAngle / (2 * semiArc) + 0.5, 0), 1)
    }

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

    private static func refineCrossing(_ lo: Double, _ hi: Double, rising: Bool, altitude: (Double) -> Double) -> Double {
        var lo = lo, hi = hi
        for _ in 0..<18 {
            let mid = (lo + hi) / 2
            if (altitude(mid) >= 0) == rising { hi = mid } else { lo = mid }
        }
        return (lo + hi) / 2
    }

    private static func observation(date: Date, latitude: Double, longitude: Double) -> (altitude: Double, hourAngle: Double, declination: Double) {
        let phi = latitude * .pi / 180
        let (rightAscension, declination) = equatorialPosition(date: date)
        let localSiderealTime = greenwichMeanSiderealTime(date: date) + longitude * .pi / 180
        let hourAngle = atan2(sin(localSiderealTime - rightAscension), cos(localSiderealTime - rightAscension))
        let altitude = asin(sin(phi) * sin(declination) + cos(phi) * cos(declination) * cos(hourAngle))
        return (altitude, hourAngle, declination)
    }

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

    private static func greenwichMeanSiderealTime(date: Date) -> Double {
        let d = julianDaysSinceJ2000(date)
        let degrees = (280.46061837 + 360.98564736629 * d).truncatingRemainder(dividingBy: 360)
        return degrees * Double.pi / 180
    }

    private static func julianDaysSinceJ2000(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 - 10_957.5
    }
}
