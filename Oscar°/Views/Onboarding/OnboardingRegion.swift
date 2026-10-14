//
//  OnboardingRegion.swift
//  Oscar°
//

import CoreLocation

enum OnboardingRegion {
    private struct Box {
        let latitudes: ClosedRange<Double>
        let longitudes: ClosedRange<Double>

        func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
            latitudes.contains(coordinate.latitude) && longitudes.contains(coordinate.longitude)
        }
    }

    private static let boxes: [Box] = [
        Box(latitudes: 34.5...72.0, longitudes: -25.0...45.0),
        Box(latitudes: 24.0...84.0, longitudes: -170.0...(-52.0)),
        Box(latitudes: 18.0...23.5, longitudes: -161.0...(-154.0)),
        Box(latitudes: 20.5...26.5, longitudes: 118.0...124.0),
        Box(latitudes: 25.7...30.6, longitudes: -19.4...(-13.0)),
    ]

    static func hasAlertCoverage(_ coordinate: CLLocationCoordinate2D) -> Bool {
        boxes.contains { $0.contains(coordinate) }
    }
}
