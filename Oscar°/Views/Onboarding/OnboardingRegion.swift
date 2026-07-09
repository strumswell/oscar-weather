//
//  OnboardingRegion.swift
//  Oscar°
//

import CoreLocation

/// Coarse boxes for where oscar-server's notification products have coverage:
/// Europe (DWD/OPERA reach) and North America (NOAA/ECCC alerts).
enum OnboardingRegion {
    private struct Box {
        let latitudes: ClosedRange<Double>
        let longitudes: ClosedRange<Double>

        func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
            latitudes.contains(coordinate.latitude) && longitudes.contains(coordinate.longitude)
        }
    }

    private static let boxes: [Box] = [
        // Europe (OPERA composite reach)
        Box(latitudes: 34.5...72.0, longitudes: -25.0...45.0),
        // Continental US + Canada incl. Alaska
        Box(latitudes: 24.0...84.0, longitudes: -170.0...(-52.0)),
        // Hawaii
        Box(latitudes: 18.0...23.5, longitudes: -161.0...(-154.0)),
    ]

    static func hasAlertCoverage(_ coordinate: CLLocationCoordinate2D) -> Bool {
        boxes.contains { $0.contains(coordinate) }
    }
}
