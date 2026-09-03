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
                Text("Ein Wettermodell ist eine Computersimulation der Atmosphäre: Aus Millionen Messwerten berechnet es, wie das Wetter in den nächsten Stunden und Tagen wird.")
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
                    summary: "Sehr feines Raster über Zentraleuropa — erkennt auch kleine Schauer und Gewitter. Ideal für die nächsten 48 Stunden.")
                WeatherModelCard(
                    name: "ECMWF IFS",
                    provider: "Europäisches Zentrum für mittelfristige Wettervorhersagen",
                    grid: "≈ 9 km Raster",
                    imageName: "layer-gfs-precip",
                    summary: "Globales Modell für den mittelfristigen Überblick mit Temperatur, Regen, Wind und Luftdruck in Drei-Stunden-Schritten.")
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
