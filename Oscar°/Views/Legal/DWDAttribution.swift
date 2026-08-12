//
//  OpenMeteoAttribution.swift
//  Oscar°
//
//  Created by Philipp Bolte on 05.07.24.
//

import SwiftUI

struct DWDAttribution: View {
    var body: some View {
        List {
                Section(header: Text("Über")) {
                    Text("Oscar verwendet Wetter- und Geodaten des Deutschen Wetterdienstes (DWD), unter anderem Radardaten, Prognosedaten aus dem ICON-Modell sowie amtliche Warnmeldungen. Datenbasis: Deutscher Wetterdienst. Die Daten werden unter den Open-Data-Nutzungsbedingungen des DWD bereitgestellt.")
                }
                Section(header: Text("Webseite")) {
                    Link("dwd.de", destination: URL(string: "https://www.dwd.de/")!)
                    Link("DWD Open Data", destination: URL(string: "https://opendata.dwd.de/")!)
                }
        }
        .navigationTitle("DWD")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DWDLabel: View {
    var body: some View {
        Label("Deutscher Wetterdienst (DWD)", systemImage: "cloud.rain.fill")
            .labelStyle(.settingsIcon(.blue))
    }
}

// MARK: - EUMETNET OPERA

struct OperaAttribution: View {
    var body: some View {
        List {
                Section(header: Text("Über")) {
                    Text("Oscar verwendet das europäische Radarkomposit des OPERA-Programms von EUMETNET, dem Zusammenschluss der europäischen Wetterdienste, für das Regenradar in Europa außerhalb Zentraleuropas sowie amtliche Warnmeldungen der europäischen Warnplattform Meteoalarm. Die Nutzung stellt keine Unterstützung oder offizielle Verbindung zu EUMETNET dar.")
                }
                Section(header: Text("Webseite")) {
                    Link("eumetnet.eu", destination: URL(string: "https://www.eumetnet.eu/")!)
                    Link("OPERA-Programm", destination: URL(string: "https://www.eumetnet.eu/activities/observations-programme/current-activities/opera/")!)
                    Link("meteoalarm.org", destination: URL(string: "https://meteoalarm.org/")!)
                }
        }
        .navigationTitle(Text(verbatim: "EUMETNET"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OperaLabel: View {
    var body: some View {
        Label {
            Text(verbatim: "EUMETNET (OPERA & Meteoalarm)")
        } icon: {
            Image(systemName: "globe.europe.africa.fill")
        }
        .labelStyle(.settingsIcon(.green))
    }
}

#Preview {
    DWDAttribution()
}
