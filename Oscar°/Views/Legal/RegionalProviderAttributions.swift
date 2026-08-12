//
//  RegionalProviderAttributions.swift
//  Oscar°
//
//  Credits for the regional radar and alert providers added over time:
//  CWA (Taiwan), REDEMET (Brazil), AEMET (Canary Islands), ECCC (Canada).
//

import SwiftUI

struct CwaAttribution: View {
    var body: some View {
        List {
            Section(header: Text("Über")) {
                Text("Oscar verwendet Daten der Central Weather Administration (CWA), der Wetterbehörde Taiwans: das QPESUMS-Radarkomposit für das Regenradar über Taiwan sowie amtliche Warnungen auf Landkreisebene. Die Nutzung stellt keine Unterstützung oder offizielle Verbindung zur CWA dar.")
            }
            Section(header: Text("Webseite")) {
                Link("cwa.gov.tw", destination: URL(string: "https://www.cwa.gov.tw/")!)
            }
        }
        .navigationTitle(Text(verbatim: "CWA"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CwaLabel: View {
    var body: some View {
        Label {
            Text(verbatim: "Central Weather Administration (CWA)")
        } icon: {
            Image(systemName: "globe.asia.australia.fill")
        }
        .labelStyle(.settingsIcon(.mint))
    }
}

struct RedemetAttribution: View {
    var body: some View {
        List {
            Section(header: Text("Über")) {
                Text("Oscar verwendet Radardaten des brasilianischen Flugwetterdienstes REDEMET (DECEA) für das Regenradar über Brasilien. Die Nutzung stellt keine Unterstützung oder offizielle Verbindung zu REDEMET oder DECEA dar.")
            }
            Section(header: Text("Webseite")) {
                Link("redemet.decea.mil.br", destination: URL(string: "https://redemet.decea.mil.br/")!)
            }
        }
        .navigationTitle(Text(verbatim: "REDEMET"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RedemetLabel: View {
    var body: some View {
        Label {
            Text(verbatim: "REDEMET (DECEA)")
        } icon: {
            Image(systemName: "globe.americas.fill")
        }
        .labelStyle(.settingsIcon(.green))
    }
}

struct AemetAttribution: View {
    var body: some View {
        List {
            Section(header: Text("Über")) {
                Text("Oscar verwendet Radardaten der Agencia Estatal de Meteorología (AEMET), des staatlichen spanischen Wetterdienstes, für das Regenradar über den Kanarischen Inseln. Die Nutzung stellt keine Unterstützung oder offizielle Verbindung zu AEMET dar.")
            }
            Section(header: Text("Webseite")) {
                Link("aemet.es", destination: URL(string: "https://www.aemet.es/")!)
            }
        }
        .navigationTitle(Text(verbatim: "AEMET"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AemetLabel: View {
    var body: some View {
        Label {
            Text(verbatim: "AEMET")
        } icon: {
            Image(systemName: "globe.europe.africa.fill")
        }
        .labelStyle(.settingsIcon(.purple))
    }
}

struct EcccAttribution: View {
    var body: some View {
        List {
            Section(header: Text("Über")) {
                Text("Oscar verwendet amtliche Wetterwarnungen von Environment and Climate Change Canada (ECCC) für Kanada. Die Nutzung stellt keine Unterstützung oder offizielle Verbindung zu ECCC dar.")
            }
            Section(header: Text("Webseite")) {
                Link("weather.gc.ca", destination: URL(string: "https://weather.gc.ca/")!)
            }
        }
        .navigationTitle(Text(verbatim: "ECCC"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EcccLabel: View {
    var body: some View {
        Label {
            Text(verbatim: "Environment and Climate Change Canada")
        } icon: {
            Image(systemName: "snowflake")
        }
        .labelStyle(.settingsIcon(.cyan))
    }
}
