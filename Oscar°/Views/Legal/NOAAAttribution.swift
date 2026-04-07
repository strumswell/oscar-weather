//
//  NOAAAttribution.swift
//  Oscar°
//
//  Created by Philipp Bolte on 07.04.26.
//

import SwiftUI

struct NOAAAttribution: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Über")) {
                    Text("Oscar verwendet Prognosedaten des Global Forecast System (GFS), einem Wettervorhersagemodell der National Centers for Environmental Prediction (NCEP), bereitgestellt durch NOAA. NOAA/NWS-Daten sind in der Regel gemeinfrei, sofern nicht anders gekennzeichnet. Die Nutzung stellt keine Unterstützung, Empfehlung oder offizielle Verbindung zu NOAA, NWS oder NCEP dar.")
                }
                Section(header: Text("Webseite")) {
                    Link("noaa.gov", destination: URL(string: "https://www.noaa.gov/")!)
                    Link("GFS bei NOAA/NCEI", destination: URL(string: "https://www.ncei.noaa.gov/products/weather-climate-models/global-forecast")!)
                    Link("NWS Disclaimer", destination: URL(string: "https://www.weather.gov/disclaimer/")!)
                }
            }
        }
        .navigationBarTitle("NOAA GFS", displayMode: .inline)
    }
}


struct NOAALabel: View {
    var body: some View {
        HStack {
            Image(systemName: "globe.americas.fill")
                .frame(width: 30, height: 30)
                .foregroundColor(.white)
                .background(Color.green)
                .cornerRadius(5)
            Text("NOAA Global Forecast System (GFS)")
        }
    }
}

#Preview {
    NOAAAttribution()
}
