//
//  GlobalViewExtensions.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.01.24.
//

import Foundation
import SwiftUI

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
