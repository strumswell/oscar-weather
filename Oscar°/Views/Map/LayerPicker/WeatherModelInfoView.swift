//
//  WeatherModelInfoView.swift
//  Oscar°
//
//  Weather-model explainer pushed from the layer picker's section headers.
//

import SwiftUI

/// Pushed from the forecast section headers: one sentence on what a weather model
/// is, then a short card per model — resolution and what it means in practice.
/// Deliberately terse; nobody reads paragraphs here.
struct WeatherModelInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Was sind Wettermodelle?")
                    .font(.headline)
                Text("Ein Wettermodell berechnet aus Millionen Messungen, wie sich die Atmosphäre entwickelt. Die Karte zeigt, was das Modell erwartet, nicht was gemessen wurde.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Wettermodelle in Oscar°")
                    .font(.headline)
                    .padding(.top, 8)
                WeatherModelCard(
                    name: "DWD ICON-D2",
                    provider: "Deutscher Wetterdienst",
                    grid: "≈ 2 km Raster",
                    imageName: "layer-icon-precip",
                    summary: "Feines Raster über Zentraleuropa, das auch einzelne Schauer und Gewitter abbilden kann. Stündlich bis 36 Stunden voraus, alle 3 Stunden ein neuer Lauf.")
                WeatherModelCard(
                    name: "ECMWF IFS",
                    provider: "Europäisches Zentrum für mittelfristige Wettervorhersagen",
                    grid: "≈ 9 km Raster",
                    imageName: "layer-gfs-precip",
                    summary: "Weltweites Modell. Stündlich bis 36 Stunden, danach in 4-Stunden-Schritten bis 3,5 Tage voraus. Alle 6 Stunden ein neuer Lauf.")
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .navigationTitle("Wettermodelle")
        .navigationBarTitleDisplayMode(.inline)
        // Keep the navigation layer clear, or it would paint an opaque background
        // behind this view and kill the sheet's Liquid Glass at the medium detent.
        .containerBackground(.clear, for: .navigation)
    }
}
