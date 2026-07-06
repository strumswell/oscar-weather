//
//  LocationService.swift
//  Oscar°
//
//  Created by Philipp Bolte on 18.11.23.
//

import Foundation
import CoreLocation
import Combine
import SwiftUI
import OSLog
#if os(watchOS)
import MapKit
#endif

@MainActor
@Observable
class Location {
    var coordinates: CLLocationCoordinate2D
    var name: String
    var countryCode: String?
    
    init() {
        coordinates = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.4)
        name = ""
        countryCode = nil
    }
}

@MainActor
@Observable
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = LocationService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "Location")
    nonisolated static let outboundCoordinateDecimalPlaces = 3
    var city = CityService.shared
    var authStatus: CLAuthorizationStatus?
    var gpsLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.4)
    private let manager = CLLocationManager()
    private let notificationCenter = NotificationCenter.default
    private var lastGeocoded: (
        coordinate: CLLocationCoordinate2D,
        name: String,
        countryCode: String?
    )?

    private override init() {
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyBest
        // Always authorization has no UI on watchOS; whenInUse is the supported scope there.
        #if os(watchOS)
        self.manager.requestWhenInUseAuthorization()
        #else
        self.manager.requestAlwaysAuthorization()
        #endif
        self.manager.startUpdatingLocation()
        self.authStatus = self.manager.authorizationStatus
        updateGPSCoordinates()
        
    }
    
    ///  Update class state with all cities from storage and the current GPS coordinates, if available
    func update() {
        city.update()
        updateGPSCoordinates()
    }
    
    /// Update class state with current user GPS coordinates, if available
    func updateGPSCoordinates() {
        if let newGPSCoordinates = getGPSCoordinates() {
            gpsLocation = newGPSCoordinates
        }
    }
    
    /// Get current user GPS coordinates, if available
    func getGPSCoordinates() -> CLLocationCoordinate2D? {
        authStatus = manager.authorizationStatus
        
        if (manager.authorizationStatus == CLAuthorizationStatus.authorizedAlways || manager.authorizationStatus == CLAuthorizationStatus.authorizedWhenInUse) {
            return manager.location?.coordinate
        }
        return nil
    }
    
    /// Get current coordinates of the user's GPS or city, if selected
    func getCoordinates() -> CLLocationCoordinate2D {
        if let selectedCity = city.getSelectedCity() {
            return CLLocationCoordinate2D(latitude: selectedCity.lat, longitude: selectedCity.lon)
        }
        return gpsLocation
    }
    
    /// Ortsteil-level overrides for small villages that CLGeocoder collapses into their Gemeinde.
    /// Each entry: (name, minLat, maxLat, minLon, maxLon) from OSM relation bounding boxes.
    private static let localityOverrides: [(name: String, minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)] = [
        ("Hessen", 52.00414699991591, 52.02869882742752, 10.763293296975537, 10.797439784181817),
    ]

    private static func localityOverride(for coordinate: CLLocationCoordinate2D) -> String? {
        localityOverrides.first {
            coordinate.latitude >= $0.minLat && coordinate.latitude <= $0.maxLat &&
            coordinate.longitude >= $0.minLon && coordinate.longitude <= $0.maxLon
        }?.name
    }

    /// Get current location name of the user's GPS reverse-geocoded cooridinates or city, if selected
    func getLocationName() async -> String {
        await getPlacemarkInfo().name
    }

    /// Get the current location name and country code, if reverse geocoding is available.
    func getPlacemarkInfo() async -> (name: String, countryCode: String?) {
        let selectedCity = city.getSelectedCity()

        if (selectedCity !== nil) {
            return (selectedCity!.label ?? "", nil)
        }

        let coordinates = gpsLocation
        if let lastGeocoded {
            let currentLocation = CLLocation(
                latitude: coordinates.latitude,
                longitude: coordinates.longitude
            )
            let cachedLocation = CLLocation(
                latitude: lastGeocoded.coordinate.latitude,
                longitude: lastGeocoded.coordinate.longitude
            )
            if currentLocation.distance(from: cachedLocation) < 2_000 {
                return (lastGeocoded.name, lastGeocoded.countryCode)
            }
        }

        if let override = LocationService.localityOverride(for: coordinates) {
            return (override, nil)
        }

        let latitude = coordinates.latitude
        let longitude = coordinates.longitude
        do {
            // Bound the reverse geocode: CLGeocoder has no timeout of its own and can
            // stall indefinitely (e.g. on a flaky network right after foregrounding),
            // which would otherwise hang the whole refresh.
            let geocoded = try await withTimeout(seconds: 6) {
                let location = CLLocation(latitude: latitude, longitude: longitude)
                #if os(watchOS)
                // CLGeocoder is deprecated AND non-functional on watchOS 26;
                // MKReverseGeocodingRequest is its designated replacement.
                return try await mapKitReverseGeocode(location)
                #else
                let placemarks = try await reverseGeocode(location)
                guard let placemark = placemarks.first else {
                    return (name: "", countryCode: String?.none)
                }
                return (name: placemark.locality ?? "", countryCode: placemark.isoCountryCode)
                #endif
            }
            if !geocoded.name.isEmpty {
                lastGeocoded = (coordinates, geocoded.name, geocoded.countryCode)
            }
            return (geocoded.name, geocoded.countryCode)
        } catch {
            Self.logger.error("Error reverse geocoding: \(error.localizedDescription, privacy: .public)")
        }

        return ("", nil)
    }
    
    /// Get current Location object of the user's GPS reverse-geocoded cooridinates or city, if selected
    func getLocation() async -> Location {
        let coordinates = getCoordinates()
        let info = await getPlacemarkInfo()
        
        let location = Location()
        location.coordinates = coordinates
        location.name = info.name
        location.countryCode = info.countryCode
        
        return location
    }
    
    internal func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            updateGPSCoordinates()
            notificationCenter.post(name: .weatherRefreshNeeded, object: nil)
        }
    }
    
    internal func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            if (location.distance(from: CLLocation(latitude: gpsLocation.latitude , longitude: gpsLocation.longitude )) > 2500) { // if distance change > 2.5 km
                gpsLocation = location.coordinate
                notificationCenter.post(name: .weatherRefreshNeeded, object: nil) // notify view
            }
        }
    }

    nonisolated static func outboundCoordinate(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: roundedOutboundCoordinate(coordinate.latitude),
            longitude: roundedOutboundCoordinate(coordinate.longitude)
        )
    }

    nonisolated static func roundedOutboundCoordinate(_ value: Double) -> Double {
        let scale = pow(10.0, Double(outboundCoordinateDecimalPlaces))
        return (value * scale).rounded() / scale
    }
}

#if os(watchOS)
/// Same single-use box rationale as `SendableGeocoder` below: `cancel()` is
/// designed to be called concurrently with the in-flight request.
private struct SendableGeocodingRequest: @unchecked Sendable {
    let request: MKReverseGeocodingRequest?
}

/// Reverse-geocodes via MapKit (the watchOS 26 replacement for CLGeocoder),
/// cancellation-aware so the enclosing timeout can unblock it.
private func mapKitReverseGeocode(_ location: CLLocation) async throws -> (name: String, countryCode: String?) {
    let box = SendableGeocodingRequest(request: MKReverseGeocodingRequest(location: location))
    guard let request = box.request else {
        return ("", nil)
    }
    return try await withTaskCancellationHandler {
        let mapItems = try await request.mapItems
        guard let item = mapItems.first else {
            return ("", String?.none)
        }
        let name = item.addressRepresentations?.cityName ?? item.name ?? ""
        return (name, item.addressRepresentations?.region?.identifier)
    } onCancel: {
        box.request?.cancel()
    }
}
#endif

/// CLGeocoder isn't `Sendable`, but `cancelGeocode()` is explicitly designed to be called
/// concurrently with an in-flight request — exactly what the cancellation handler does below.
/// Boxing the single-use geocoder lets the operation and cancel closures share it across the
/// `sending`/`@Sendable` boundary without weakening any real guarantee.
private struct SendableGeocoder: @unchecked Sendable {
    let geocoder = CLGeocoder()
}

/// Reverse-geocodes a location, cancellation-aware so an enclosing timeout can unblock it:
/// cancelling the task calls `cancelGeocode()`, which fires the completion handler instead of
/// leaving the continuation (and any awaiting task group) suspended forever.
private func reverseGeocode(_ location: CLLocation) async throws -> [CLPlacemark] {
    let box = SendableGeocoder()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            box.geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let placemarks = placemarks {
                    continuation.resume(returning: placemarks)
                } else {
                    continuation.resume(throwing: NSError(domain: "CLGeocoderError", code: 0, userInfo: nil))
                }
            }
        }
    } onCancel: {
        box.geocoder.cancelGeocode()
    }
}

private struct TimeoutError: Error {}

/// Runs `operation`, throwing `TimeoutError` if it does not finish within `seconds`.
/// The operation task is cancelled when the timeout wins.
private func withTimeout<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
