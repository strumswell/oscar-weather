//
//  NowViewModel.swift
//  Weather
//
//  Created by Philipp Bolte on 17.12.20.
//
import Foundation
import CoreLocation
import Combine

class NowViewModel: NSObject, CLLocationManagerDelegate, ObservableObject {
    
    private let locationManager = CLLocationManager()
    private let defaultCoordinates = CLLocationCoordinate2D(latitude: 52.41, longitude: 12.55)
    
    let objectWillChange = ObservableObjectPublisher()
    var coordinates: CLLocationCoordinate2D? {
        willSet {
            objectWillChange.send()
        }
    }
    var weather: WeatherResponse? {
        willSet {
            objectWillChange.send()
        }
    }
    
    var placemark: CLPlacemark? {
        willSet {
            objectWillChange.send()
        }
    }

    
    override init() {
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.requestAlwaysAuthorization()
        self.locationManager.startUpdatingLocation()
        self.coordinates = defaultCoordinates
    }
    
    /*
     * Fetch users current coordinates
     */
    func fetchCurrentCoordinates() {
        if (self.locationManager.authorizationStatus == CLAuthorizationStatus.authorizedAlways || self.locationManager.authorizationStatus == CLAuthorizationStatus.authorizedWhenInUse) {
            self.coordinates = self.locationManager.location?.coordinate ?? defaultCoordinates
        }
    }
    
    /*
     * Fetch placemark object of users current location
     */
    func fetchCurrentPlacemark() {
        let coordinate = CLLocation.init(
            latitude: self.coordinates?.latitude ?? defaultCoordinates.latitude,
            longitude: self.coordinates?.longitude ?? defaultCoordinates.longitude
        )
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(coordinate,
                                        completionHandler: {
                                            (placemarks, error) in
                                            if error == nil {
                                                let firstLocation = placemarks?[0]
                                                self.placemark = firstLocation
                                            } else {
                                                self.placemark = CLPlacemark()
                                            }
                                        })
    }
    
    /*
     * Fetch weather of current user location via external service
     * Credits: https://www.hackingwithswift.com/books/ios-swiftui/sending-and-receiving-codable-data-with-urlsession-and-swiftui
     */
    func fetchCurrentWeather() {
        let coordinate = self.coordinates ?? defaultCoordinates
        guard let url = URL(string: "https://?lat=\(coordinate.latitude)&lon=\(coordinate.longitude)&key=") else {
            print("Invalid URL")
            return
        }
        let request = URLRequest(url: url)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data {
                if let decodedResponse = try? JSONDecoder().decode(WeatherResponse.self, from: data) {
                    DispatchQueue.main.async {
                        self.weather = decodedResponse.self
                    }
                    return
                }
            }
            print("Fetch failed: \(error?.localizedDescription ?? "Unknown error")")
        }.resume()
    }
    
    /*
     * If the user shares its current location, update all states
     */
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            fetchCurrentCoordinates()
            fetchCurrentPlacemark()
            fetchCurrentWeather()
        }
    }
}
