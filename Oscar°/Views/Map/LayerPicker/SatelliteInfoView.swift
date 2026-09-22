//
//  SatelliteInfoView.swift
//  Oscar°
//
//  Satellite-source explainer pushed from the layer picker's satellite section
//  header — the sibling of RadarInfoView.
//

import SwiftUI

/// Pushed from the satellite section header: what the cloud layer actually is
/// (cloud optical thickness from the MTG OCA product), then a source card with the
/// hard numbers. Terse like RadarInfoView/WeatherModelInfoView.
struct SatelliteInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Was zeigt die Wolken-Ebene?")
                    .font(.headline)
                Text("Der Wettersatellit Meteosat beobachtet Europa, Afrika und den Atlantik aus 36.000 km Höhe. Alle 10 Minuten berechnet EUMETSAT daraus, wie dick die Wolken sind. Oscar zeigt dünne Schleier zart und dicke Wolken deckend, auch Nebel und tiefe Bewölkung, bei Tag und Nacht. Aus der Zugbewegung rechnet Oscar knapp 2 Stunden voraus.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Satellitenquelle in Oscar°")
                    .font(.headline)
                    .padding(.top, 8)
                WeatherModelCard(
                    name: "EUMETSAT",
                    provider: "Europäische Organisation für Wettersatelliten",
                    grid: "≈ 5 km · 10 Min.",
                    imageName: "layer-clouds",
                    summary: "Meteosat der dritten Generation über 0° Länge, Produkt Optimal Cloud Analysis. Zum Rand der Erdscheibe hin wird das Bild gröber. Contains modified EUMETSAT Meteosat data.")
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .navigationTitle("Satellit")
        .navigationBarTitleDisplayMode(.inline)
        // Keep the navigation layer clear, or it would paint an opaque background
        // behind this view and kill the sheet's Liquid Glass at the medium detent.
        .containerBackground(.clear, for: .navigation)
    }
}

#Preview {
    NavigationStack {
        SatelliteInfoView()
    }
    .preferredColorScheme(.dark)
}
