//
//  LocationManager.swift
//  LocationManager
//
//  Created by Philipp Bolte on 18.08.21.
//

import Foundation
import CoreLocation
import Combine
import SwiftUI

class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    private let manager = CLLocationManager()
    private let nc = NotificationCenter.default
    
    @Published var authStatus: CLAuthorizationStatus?
    @Published var gpsLocation: CLLocationCoordinate2D?
    
    override init() {
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyBest
        self.manager.requestAlwaysAuthorization()
        self.manager.startUpdatingLocation()
        self.authStatus = self.manager.authorizationStatus
    }

    func update() {
        fetchCurrentCoordinates()
    }
    
    internal func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {        
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            fetchCurrentCoordinates()
            nc.post(name: Notification.Name("ChangedLocation"), object: nil)
        }
    }
    
    internal func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            if (location.distance(from: CLLocation(latitude: (gpsLocation?.latitude ?? 52.01), longitude: (gpsLocation?.longitude ?? 10.77))) > 2500) { // if distance change > 2.5 km
                self.gpsLocation = location.coordinate
                nc.post(name: Notification.Name("ChangedLocation"), object: nil) // notify view
            }
        }
    }
    
    private func fetchCurrentCoordinates() {
        self.authStatus = self.manager.authorizationStatus
        
        if (self.manager.authorizationStatus == CLAuthorizationStatus.authorizedAlways || self.manager.authorizationStatus == CLAuthorizationStatus.authorizedWhenInUse) {
            self.gpsLocation = self.manager.location?.coordinate
        }
    }
}
