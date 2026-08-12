//
//  NOAAAttribution.swift
//  Oscar°
//
//  Created by Philipp Bolte on 07.04.26.
//

import SwiftUI

struct NOAAAttribution: View {
    var body: some View {
        List {
                Section(header: Text("Über")) {
                    Text("Oscar verwendet Daten der US-Wetterbehörde NOAA: Prognosedaten aus den Modellen GFS und HRRR, das MRMS-Radarkomposit für das Regenradar über den USA sowie amtliche Warnungen des National Weather Service (NWS). NOAA/NWS-Daten sind in der Regel gemeinfrei, sofern nicht anders gekennzeichnet. Die Nutzung stellt keine Unterstützung, Empfehlung oder offizielle Verbindung zu NOAA oder NWS dar.")
                }
                Section(header: Text("Webseite")) {
                    Link("noaa.gov", destination: URL(string: "https://www.noaa.gov/")!)
                    Link("GFS bei NOAA/NCEI", destination: URL(string: "https://www.ncei.noaa.gov/products/weather-climate-models/global-forecast")!)
                    Link("NWS Disclaimer", destination: URL(string: "https://www.weather.gov/disclaimer/")!)
                }
        }
        .navigationTitle(Text(verbatim: "NOAA"))
        .navigationBarTitleDisplayMode(.inline)
    }
}


struct NOAALabel: View {
    var body: some View {
        Label {
            Text(verbatim: "NOAA & NWS")
        } icon: {
            Image(systemName: "globe.americas.fill")
        }
        .labelStyle(.settingsIcon(.indigo))
    }
}

#Preview {
    NOAAAttribution()
}
