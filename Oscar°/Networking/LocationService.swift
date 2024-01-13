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
    var city = CityServiceNew()
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
    
    /// Get current location name of the user's GPS reverse-geocoded cooridinates or city, if selected
    func getLocationName() async -> String {
        let selectedCity = city.getSelectedCity()
        
        if (selectedCity !== nil) {
            return selectedCity!.label ?? ""
        }
            
        let geocoder = CLGeocoder()
        let coordinates = gpsLocation
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
