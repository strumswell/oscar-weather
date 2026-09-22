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
                Text("Wetterradare messen, wo es gerade regnet oder schneit. Aus der Bewegung der letzten Bilder rechnet Oscar die nächsten 1,5 bis 2 Stunden voraus. Alles nach der LIVE-Markierung ist diese Kurzprognose. Schauer, die in der Zeit neu entstehen oder sich auflösen, erfasst sie nicht.")
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
                    summary: "17 Radare über Deutschland und den Grenzregionen. Die Kurzprognose für knapp 2 Stunden liefert der DWD selbst.")
                WeatherModelCard(
                    name: "EUMETNET",
                    provider: "Verbund der europäischen Wetterdienste",
                    grid: "≈ 2 km · 15 Min.",
                    imageName: "layer-radar-europe",
                    summary: "Gemeinsames Radarbild der europäischen Wetterdienste. Gemessen wird alle 15 Minuten, die Bilder dazwischen berechnet Oscar.")
                WeatherModelCard(
                    name: "NOAA MRMS",
                    provider: "US-Wetterbehörde NOAA",
                    grid: "≈ 2 km · 2 Min.",
                    imageName: "layer-radar-usa",
                    summary: "Radarbild der 48 zusammenhängenden US-Bundesstaaten, alle 2 Minuten neu.")
                WeatherModelCard(
                    name: "CWA",
                    provider: "Wetterbehörde Taiwans",
                    grid: "≈ 1,4 km · 10 Min.",
                    imageName: "layer-radar-taiwan",
                    summary: "Radarbild über Taiwan und den umliegenden Inseln. Die Bilder zwischen den Messungen berechnet Oscar.")
                WeatherModelCard(
                    name: "REDEMET",
                    provider: "Flugwetterdienst Brasiliens (DECEA)",
                    grid: "≈ 2 km · 20 Min.",
                    imageName: "layer-radar-brasil",
                    summary: "Rund 29 Radarstandorte, die nicht gleichzeitig melden. Deshalb kann das Bild Lücken haben.")
                WeatherModelCard(
                    name: "AEMET",
                    provider: "Spanischer Wetterdienst (AEMET)",
                    grid: "≈ 1 km · 10 Min.",
                    imageName: "layer-radar-canarias",
                    summary: "Zwei Radare auf Gran Canaria und Teneriffa. Berge wie der Teide können einzelne Bereiche verdecken.")
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
