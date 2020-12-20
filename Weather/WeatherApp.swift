//
//  WeatherApp.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.
//

import SwiftUI

@main
struct WeatherApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                NowView()
                .tabItem {
                    Image(systemName: "sun.max")
                    Text("Jetzt")
                }.tag(0)
                ZStack() {
                    Text("Hello!")
                }
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Vorhersage")
                }.tag(1)
                
                ZStack() {
                    Text("Hello!")
                }
                .tabItem {
                    Image(systemName: "map")
                    Text("Radar")
                }.tag(2)
                
                ZStack() {
                    Text("Hello!")
                }
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Einstellungen")
                }.tag(3)
            }
            .accentColor(.white)
        }
    }
}
