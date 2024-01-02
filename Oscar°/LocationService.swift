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

class LocationService {
    @Published private var locationManager = LocationManager()
    @Published private var cityService = CityService()
    
    func update() {
        locationManager.update()
        cityService.update()
    }
    
    func getCoordinates() -> CLLocationCoordinate2D {
        if let selectedCity = cityService.getSelectedCity() {
            return CLLocationCoordinate2D(latitude: selectedCity.lat, longitude: selectedCity.lon)
        }
        return locationManager.getLocation()
    }
    
    func getLocationName() async -> String {
        let selectedCity = cityService.getSelectedCity()
        
        if (selectedCity !== nil) {
            return selectedCity!.label ?? ""
        }
            
        let geocoder = CLGeocoder()
        let coordinates = locationManager.getLocation()
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
    
    func getLocation() async -> Location {
        let coordinates = getCoordinates()
        let name = await getLocationName()
        
        let location = Location()
        location.coordinates = coordinates
        location.name = name
        
        return location
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
