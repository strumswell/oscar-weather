//
//  OpenMeteoAttribution.swift
//  Oscar°
//
//  Created by Philipp Bolte on 05.07.24.
//

import SwiftUI

struct BrightSkyAttribution: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Über")) {
                    Text("BrightSky ist eine Open-Source-Wetter-API, die offene Wetterdaten vom DWD aufbereiten und für Oscar in Form von Wetterwarnung und Radardaten für Deutschland zur Verfügung stellen. Oscar nutzt als nicht-kommerzielle App den kostenlosen Zugang zu BrightSky, unterstützt das Projekt aber mit einer monatlichen Spende von fünf Euro.")
                }
                Section(header: Text("Webseite")) {
                    Link(destination: URL(string: "https://brightsky.dev/")!, label: {
                        Text("brightsky.dev")
                    })                }
                Section(header: Text("Datenquellen")) {
                    Link(destination: URL(string: "https://dwd.de/")!, label: {
                        Text("Deutscher Wetterdienst (DWD)")
                    })
                }
            }
        }
        .navigationBarTitle("BrightSky", displayMode: .inline)
    }
}

struct BrightSkyLabel: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            Image(systemName: "network")
                .frame(width: 30, height: 30)
                .foregroundColor(.white)
                .background(Color.green)
                .cornerRadius(5)
            Text("BrightSky")
        }
    }
}

#Preview {
    BrightSkyAttribution()
}
