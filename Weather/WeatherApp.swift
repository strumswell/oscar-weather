//
//  WeatherApp.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.
//

import SwiftUI
@main
struct WeatherApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            NowView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
