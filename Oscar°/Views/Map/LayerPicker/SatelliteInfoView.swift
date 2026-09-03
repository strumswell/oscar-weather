//
//  SatelliteInfoView.swift
//  Oscar°
//
//  Satellite-source explainer pushed from the layer picker's satellite section
//  header — the sibling of RadarInfoView.
//

import SwiftUI

/// Pushed from the satellite section header: what the cloud layer actually is
/// (a real infrared scan from geostationary orbit), then a source card with the
/// hard numbers. Terse like RadarInfoView/WeatherModelInfoView.
struct SatelliteInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Was zeigt die Wolken-Ebene?")
                    .font(.headline)
                Text("Echte Aufnahmen des Wettersatelliten Meteosat, der die Erde geostationär aus rund 36.000 km Höhe beobachtet. Alle 15 Minuten kommt ein neues Bild, aufgenommen im Infrarot und damit auch nachts: je höher und dichter die Bewölkung, desto heller erscheint sie. Aus der Zugbewegung berechnet Oscar die Zwischenschritte und eine Kurzprognose; alles hinter der LIVE-Markierung ist berechnet.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Satellitenquelle in Oscar°")
                    .font(.headline)
                    .padding(.top, 8)
                WeatherModelCard(
                    name: "EUMETSAT",
                    provider: "Europäische Organisation für Wettersatelliten",
                    grid: "≈ 5 km · 15 Min.",
                    imageName: "layer-clouds",
                    summary: "Meteosat (MSG) auf 0° Länge, Instrument SEVIRI, Infrarot 10,8 μm. Volle Erdscheibe alle 15 Minuten mit etwa 3 km Auflösung im Bildzentrum; zum Rand der Scheibe wird das Bild flacher und gröber. Contains modified EUMETSAT Meteosat data.")
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
