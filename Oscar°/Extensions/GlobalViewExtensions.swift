//
//  GlobalViewExtensions.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.01.24.
//

import Foundation
import SwiftUI
import CoreLocation

extension View {
    public func getCurrentHour() -> Int {
        let currentDate = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: currentDate)
        return hour
    }
    
    public func roundTemperatureString(temperature: Double?) -> String {
        if (temperature == nil) {
            return ""
        } else {
            return "\(Int(temperature?.rounded() ?? 0))°"
        }
    }
}

extension CLLocationCoordinate2D {
    enum Country {
            case spain
            case portugal
            case unknown

            var description: String {
                switch self {
                case .spain:
                    return "Spain"
                case .portugal:
                    return "Portugal"
                case .unknown:
                    return "Unknown"
                }
            }
        }
    
    struct CountryBoundary {
        var minLatitude: Double
        var maxLatitude: Double
        var minLongitude: Double
        var maxLongitude: Double

        func contains(coordinate: CLLocationCoordinate2D) -> Bool {
            return (coordinate.latitude >= minLatitude && coordinate.latitude <= maxLatitude) &&
                   (coordinate.longitude >= minLongitude && coordinate.longitude <= maxLongitude)
        }
    }

    private static let spainBoundary = CountryBoundary(minLatitude: 36.0, maxLatitude: 43.8, minLongitude: -9.0, maxLongitude: 3.4)
    private static let portugalBoundary = CountryBoundary(minLatitude: 36.9, maxLatitude: 42.2, minLongitude: -9.6, maxLongitude: -6.2)

    func country() -> Country {
        if CLLocationCoordinate2D.spainBoundary.contains(coordinate: self) {
            return .spain
        } else if CLLocationCoordinate2D.portugalBoundary.contains(coordinate: self) {
            return .portugal
        } else {
            return .unknown
        }
    }
}
