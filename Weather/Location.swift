//
//  Location.swift
//  Weather
//
//  Created by Philipp Bolte on 24.09.20.
//

import Foundation
import CoreLocation
import Combine
import WidgetKit

class LocationViewModel: NSObject, ObservableObject{
    
    @Published var userLatitude: Double = 52.42
    @Published var userLongitude: Double = 12.52
    
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.requestAlwaysAuthorization()
        self.locationManager.showsBackgroundLocationIndicator = true
        self.locationManager.startUpdatingLocation()
    }
}

extension LocationViewModel: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLatitude = location.coordinate.latitude
        userLongitude = location.coordinate.longitude
    }
}
