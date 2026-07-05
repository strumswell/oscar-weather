//
//  OpenMeteoAttribution.swift
//  Oscar°
//
//  Created by Philipp Bolte on 05.07.24.
//

import SwiftUI

struct DWDAttribution: View {
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Über")) {
                    Text("Oscar verwendet Wetter- und Geodaten des Deutschen Wetterdienstes (DWD), unter anderem Radardaten sowie Prognosedaten aus dem ICON-D2-Modell. Datenbasis: Deutscher Wetterdienst. Die Daten werden unter den Open-Data-Nutzungsbedingungen des DWD bereitgestellt.")
                }
                Section(header: Text("Webseite")) {
                    Link("dwd.de", destination: URL(string: "https://www.dwd.de/")!)
                    Link("DWD Open Data", destination: URL(string: "https://opendata.dwd.de/")!)
                }
            }
        }
        .navigationTitle("DWD")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DWDLabel: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            Image(systemName: "cloud.rain.fill")
                .frame(width: 30, height: 30)
                .foregroundStyle(.white)
                .background(Color.green)
                .clipShape(.rect(cornerRadius: 5))
            Text("Deutscher Wetterdienst (DWD)")
        }
    }
}

// MARK: - EUMETNET OPERA

struct OperaAttribution: View {
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Über")) {
                    Text("Oscar verwendet das europäische Radarkomposit des OPERA-Programms von EUMETNET, dem Zusammenschluss der europäischen Wetterdienste, für das Regenradar in Europa außerhalb Zentraleuropas. Die Nutzung stellt keine Unterstützung oder offizielle Verbindung zu EUMETNET dar.")
                }
                Section(header: Text("Webseite")) {
                    Link("eumetnet.eu", destination: URL(string: "https://www.eumetnet.eu/")!)
                    Link("OPERA-Programm", destination: URL(string: "https://www.eumetnet.eu/activities/observations-programme/current-activities/opera/")!)
                }
            }
        }
        .navigationTitle("EUMETNET OPERA")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OperaLabel: View {
    var body: some View {
        HStack {
            Image(systemName: "globe.europe.africa.fill")
                .frame(width: 30, height: 30)
                .foregroundStyle(.white)
                .background(Color.green)
                .clipShape(.rect(cornerRadius: 5))
            Text("EUMETNET OPERA")
        }
    }
}

#Preview {
    DWDAttribution()
}
