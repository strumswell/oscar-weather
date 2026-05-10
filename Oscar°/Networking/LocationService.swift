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

@Observable
class Location {
    var coordinates: CLLocationCoordinate2D
    var name: String
    
    init() {
        coordinates = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.4)
        name = ""
    }
}

@Observable
class LocationService: NSObject, CLLocationManagerDelegate  {
    static let shared = LocationService()
    static let outboundCoordinateDecimalPlaces = 3
    var city = CityServiceNew.shared
    var authStatus: CLAuthorizationStatus?
    var gpsLocation: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.4)
    private let manager = CLLocationManager()
    private let notificationCenter = NotificationCenter.default

    private override init() {
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyBest
        self.manager.requestAlwaysAuthorization()
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
        let selectedCity = city.getSelectedCity()

        if (selectedCity !== nil) {
            return selectedCity!.label ?? ""
        }

        let coordinates = gpsLocation
        if let override = LocationService.localityOverride(for: coordinates) {
            return override
        }

        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinates.latitude, longitude: coordinates.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                return placemark.locality ?? ""
            }
        } catch {
            print("Error reverse geocoding: \(error)")
        }

        return ""
    }
    
    /// Get current Location object of the user's GPS reverse-geocoded cooridinates or city, if selected
    func getLocation() async -> Location {
        let coordinates = getCoordinates()
        let name = await getLocationName()
        
        let location = Location()
        location.coordinates = coordinates
        location.name = name
        
        return location
    }
    
    internal func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            updateGPSCoordinates()
            notificationCenter.post(name: Notification.Name("ChangedLocation"), object: nil)
        }
    }
    
    internal func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            if (location.distance(from: CLLocation(latitude: gpsLocation.latitude , longitude: gpsLocation.longitude )) > 2500) { // if distance change > 2.5 km
                gpsLocation = location.coordinate
                notificationCenter.post(name: Notification.Name("ChangedLocation"), object: nil) // notify view
            }
        }
    }

    static func outboundCoordinate(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: roundedOutboundCoordinate(coordinate.latitude),
            longitude: roundedOutboundCoordinate(coordinate.longitude)
        )
    }

    static func roundedOutboundCoordinate(_ value: Double) -> Double {
        let scale = pow(10.0, Double(outboundCoordinateDecimalPlaces))
        return (value * scale).rounded() / scale
    }
}

extension CLGeocoder {
    func reverseGeocodeLocation(_ location: CLLocation) async throws -> [CLPlacemark] {
        return try await withCheckedThrowingContinuation { continuation in
            self.reverseGeocodeLocation(location) { placemarks, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let placemarks = placemarks {
                    continuation.resume(returning: placemarks)
                } else {
                    continuation.resume(throwing: NSError(domain: "CLGeocoderError", code: 0, userInfo: nil))
                }
            }
        }
    }
}
