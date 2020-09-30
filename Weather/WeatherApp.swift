//
//  WeatherApp.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.
//

import SwiftUI

@main
struct WeatherApp: App {
    @ObservedObject var locationViewModel = LocationViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
