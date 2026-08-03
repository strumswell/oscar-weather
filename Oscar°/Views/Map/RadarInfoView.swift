//
//  RadarInfoView.swift
//  Oscar°
//
//  Radar-source explainer pushed from the layer picker's radar section header.
//

import SwiftUI

/// Pushed from the radar section header: one sentence on what the radar layer
/// shows, then a short card per coverage — provider, resolution, measurement
/// cadence and what to expect. Terse like WeatherModelInfoView.
struct RadarInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Was zeigt das Regenradar?")
                    .font(.headline)
                Text("Wetterradare messen, wo es gerade regnet oder schneit. Oscar verbindet die Messung mit einer Kurzprognose: Aus der Zugbewegung des Niederschlags werden die nächsten ein bis zwei Stunden berechnet. Alles hinter der LIVE-Markierung ist berechnet — je weiter voraus, desto unsicherer.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Radarquellen in Oscar°")
                    .font(.headline)
                    .padding(.top, 8)
                WeatherModelCard(
                    name: "DWD",
                    provider: "Deutscher Wetterdienst",
                    grid: "≈ 1 km · 5 Min.",
                    imageName: "layer-radar-germany",
                    summary: "Radarkomposit über Deutschland und den Nachbarländern. Neue Messung alle 5 Minuten, Kurzprognose für die nächsten 2 Stunden.")
                WeatherModelCard(
                    name: "EUMETNET",
                    provider: "Verbund der europäischen Wetterdienste",
                    grid: "≈ 2 km · 15 Min.",
                    imageName: "layer-radar-europe",
                    summary: "Europaweites Komposit (OPERA-Programm) aus den Radaren von über 30 Ländern. Neue Messung alle 15 Minuten; die Zwischenschritte berechnet Oscar aus der Zugbewegung.")
                WeatherModelCard(
                    name: "NOAA MRMS",
                    provider: "US-Wetterbehörde NOAA",
                    grid: "≈ 1 km · 2 Min.",
                    imageName: "layer-radar-usa",
                    summary: "Multi-Radar-Komposit über den zusammenhängenden USA mit sehr dichter Aktualisierung aus rund 180 Radaren.")
                WeatherModelCard(
                    name: "CWA",
                    provider: "Wetterbehörde Taiwans",
                    grid: "≈ 1,4 km · 10 Min.",
                    imageName: "layer-radar-taiwan",
                    summary: "QPESUMS-Komposit der taiwanischen Wetterbehörde über Taiwan und seinen Inselgruppen.")
                WeatherModelCard(
                    name: "REDEMET",
                    provider: "Flugwetterdienst Brasiliens (DECEA)",
                    grid: "≈ 2 km · 20 Min.",
                    imageName: "layer-radar-brasil",
                    summary: "Mosaik aus rund 29 Radarstandorten des brasilianischen Flugwetterdienstes. Einzelne Standorte melden unregelmäßig, Lücken sind möglich.")
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .navigationTitle("Regenradar")
        .navigationBarTitleDisplayMode(.inline)
        // Keep the navigation layer clear, or it would paint an opaque background
        // behind this view and kill the sheet's Liquid Glass at the medium detent.
        .containerBackground(.clear, for: .navigation)
    }
}

#Preview {
    NavigationStack {
        RadarInfoView()
    }
    .preferredColorScheme(.dark)
}
