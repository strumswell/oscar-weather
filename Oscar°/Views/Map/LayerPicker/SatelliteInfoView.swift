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
                Text("Die Wolken-Ebene beruht auf Messungen des Wettersatelliten Meteosat, der die Erde geostationär aus rund 36.000 km Höhe beobachtet. Alle 10 Minuten wertet EUMETSAT die Aufnahmen aus und berechnet für jeden Bildpunkt, wie dicht die Wolke dort ist. Genau das zeigt Oscar: dünne Schleier erscheinen zart, dicke Wolken deckend. Das funktioniert bei Tag und bei Nacht. Aus der Zugbewegung berechnet Oscar die Zwischenschritte und eine Kurzprognose. Alles hinter der LIVE-Markierung ist berechnet.")
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
                    summary: "Meteosat der dritten Generation (MTG) auf 0° Länge, Instrument FCI. Oscar nutzt das Produkt Optimal Cloud Analysis und daraus die optische Dicke der Wolken. Volle Erdscheibe alle 10 Minuten mit etwa 2 km Auflösung im Bildzentrum. Zum Rand der Scheibe wird das Bild flacher und gröber. Contains modified EUMETSAT Meteosat data.")
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
