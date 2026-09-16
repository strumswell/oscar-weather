import CoreLocation
import Foundation
import simd

/// One tracked cell from `/radar/{region}/cells` — everything the overlay and the
/// tap sheet need, including the projected track and the footprint hull.
struct StormCellInfo: Identifiable {
    let id: Int
    let center: CLLocationCoordinate2D
    let areaKm2: Double
    let peakMmh: Double
    let meanMmh: Double
    let velocityKmh: Double
    let bearingDeg: Double
    /// Extrapolated centroids at +15/+30/+45/+60 min.
    let path: [CLLocationCoordinate2D]
    /// Convex-hull outline (closed ring); empty when the server sent none.
    let footprint: [CLLocationCoordinate2D]

    /// Equivalent circular radius — the footprint scale for cones and ETA slop.
    var radiusKm: Double { (areaKm2 / .pi).squareRoot() }

    /// Nearest approach of the projected track (center → +60 min) to `target`:
    /// minutes along the track and the miss distance. nil when there is no track.
    func closestApproach(to target: CLLocationCoordinate2D) -> (minutes: Double, distanceKm: Double)? {
        let points = [center] + path
        guard points.count >= 2 else { return nil }
        let cosLat = max(0.2, cos(target.latitude * .pi / 180))
        // Local km plane centered on the target.
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
