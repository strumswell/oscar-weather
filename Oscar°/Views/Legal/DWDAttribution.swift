//
//  OpenMeteoAttribution.swift
//  Oscar°
//
//  Created by Philipp Bolte on 05.07.24.
//

import SwiftUI

struct DWDAttribution: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Über")) {
                    Text("Der Deutsche Wetterdienst (DWD) stellt über deren GeoServer den Radar-Layer für Zentraleuropa kostenlos bereit. Zudem kommen sämtliche Daten des DWD durch andere Dritt-Services wie Open-Meteo und BrightSky in Oscar zum Einsatz.")
                }
                Section(header: Text("Webseite")) {
                    Link(destination: URL(string: "https://www.dwd.de/")!, label: {
                        Text("dwd.de")
                    })
                }
            }
        }
        .navigationBarTitle("DWD", displayMode: .inline)
    }
}

struct DWDLabel: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            Image(systemName: "cloud.rain.fill")
                .frame(width: 30, height: 30)
                .foregroundColor(.white)
                .background(Color.green)
                .cornerRadius(5)
            Text("Deutscher Wetterdienst (DWD)")
        }
    }
}

#Preview {
    DWDAttribution()
}
