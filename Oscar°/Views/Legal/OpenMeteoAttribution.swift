//
//  OpenMeteoAttribution.swift
//  Oscar°
//
//  Created by Philipp Bolte on 05.07.24.
//

import SwiftUI

struct OpenMeteoAttribution: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Über")) {
                    Text("Open-Meteo ist eine Open-Source-Wetter-API, die offene Wetterdaten von verschiedenen internationalen Wetterdiensten sammelt. Oscar nutzt als nicht-kommerzielle App den kostenlosen Zugang zu Open-Meteo, unterstützt das Projekt aber mit einer monatlichen Spende von fünf Euro.")
                }
                Section(header: Text("Lizenz")) {
                    Text("Attribution 4.0 International (CC BY 4.0)")
                }
                Section(header: Text("Webseite")) {
                    Link(destination: URL(string: "https://open-meteo.com/")!, label: {
                        Text("open-meteo.com")
                    })                }
                Section(header: Text("Datenquellen")) {
                    Link(destination: URL(string: "https://www.dwd.de/")!, label: {
                        Text("ICON - Deutscher Wetterdienst (DWD)")
                    })
                    Link(destination: URL(string: "https://www.noaa.gov/")!, label: {
                        Text("GFS & HRRR - NOAA")
                    })
                    Link(destination: URL(string: "https://meteofrance.com/")!, label: {
                        Text("ARPEGE & AROME - Météo-France")
                    })
                    Link(destination: URL(string: "https://www.ecmwf.int/")!, label: {
                        Text("IFS & AIFS - ECMWF")
                    })
                    Link(destination: URL(string: "https://www.jma.go.jp/")!, label: {
                        Text("MSM & GSM - JMA")
                    })
                    Link(destination: URL(string: "https://www.met.no/")!, label: {
                        Text("MET Nordic - MET Norway")
                    })
                    Link(destination: URL(string: "https://www.knmi.nl/")!, label: {
                        Text("HARMONIE - KNMI")
                    })
                    Link(destination: URL(string: "https://www.dmi.dk/")!, label: {
                        Text("HARMONIE - DMI")
                    })
                    Link(destination: URL(string: "https://weather.gc.ca/")!, label: {
                        Text("GEM - Canadian Weather Service")
                    })
                    Link(destination: URL(string: "https://www.cma.gov.cn/en/")!, label: {
                        Text("GFS GRAPES - China Meteorological Administration (CMA)")
                    })
                    Link(destination: URL(string: "http://www.bom.gov.au/")!, label: {
                        Text("ACCESS-G - Australian Bureau of Meteorology (BOM)")
                    })
                    Link(destination: URL(string: "https://www.arpae.it/it")!, label: {
                        Text("COSMO 2I & 5M - AM ARPAE ARPAP")
                    })
                }
            }
        }
        .navigationBarTitle("Open-Meteo", displayMode: .inline)
    }
}

struct OpenMeteoLabel: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack {
            Image(systemName: "sun.max.fill")
                .frame(width: 30, height: 30)
                .foregroundColor(.white)
                .background(Color.green)
                .cornerRadius(5)
            Text("Open-Meteo")
        }
    }
}

#Preview {
    OpenMeteoAttribution()
}
