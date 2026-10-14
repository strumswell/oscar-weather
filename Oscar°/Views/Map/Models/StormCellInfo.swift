import CoreLocation
import Foundation
import simd

struct StormCellInfo: Identifiable {
    let id: Int
    let center: CLLocationCoordinate2D
    let areaKm2: Double
    let peakMmh: Double
    let meanMmh: Double
    let velocityKmh: Double
    let bearingDeg: Double
    let path: [CLLocationCoordinate2D]
    let footprint: [CLLocationCoordinate2D]

    var radiusKm: Double { (areaKm2 / .pi).squareRoot() }

    func closestApproach(to target: CLLocationCoordinate2D) -> (minutes: Double, distanceKm: Double)? {
        let points = [center] + path
        guard points.count >= 2 else { return nil }
        let cosLat = max(0.2, cos(target.latitude * .pi / 180))
        let local = points.map { point in
            SIMD2((point.longitude - target.longitude) * 111.320 * cosLat,
                  (point.latitude - target.latitude) * 110.574)
        }
        var best: (minutes: Double, distanceKm: Double)?
        for i in 0..<(local.count - 1) {
            let a = local[i], b = local[i + 1]
            let ab = b - a
            let lengthSquared = simd_length_squared(ab)
            let t = lengthSquared > 0 ? min(1, max(0, -simd_dot(a, ab) / lengthSquared)) : 0
            let distance = simd_length(a + ab * t)
            let minutes = 15 * (Double(i) + t)
            if best == nil || distance < best!.distanceKm {
                best = (minutes, distance)
            }
        }
        return best
    }
}
