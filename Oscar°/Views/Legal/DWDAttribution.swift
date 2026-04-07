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
                    Text("Oscar verwendet Wetter- und Geodaten des Deutschen Wetterdienstes (DWD), unter anderem Radardaten sowie Prognosedaten aus dem ICON-D2-Modell. Datenbasis: Deutscher Wetterdienst. Die Daten werden unter den Open-Data-Nutzungsbedingungen des DWD bereitgestellt.")
                }
                Section(header: Text("Webseite")) {
                    Link("dwd.de", destination: URL(string: "https://www.dwd.de/")!)
                    Link("DWD Open Data", destination: URL(string: "https://opendata.dwd.de/")!)
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
