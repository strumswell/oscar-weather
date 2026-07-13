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
                    name: "NOAA GFS",
                    provider: "US-Wetterbehörde NOAA",
                    grid: "≈ 25 km Raster",
                    imageName: "layer-gfs-precip",
                    summary: "Gröberes Raster, dafür weltweit — gut für den großen Überblick. Einzelne Schauer können verschwimmen.")
                WeatherModelCard(
                    name: "ECMWF IFS",
                    provider: "Europäisches Zentrum für mittelfristige Wettervorhersagen",
                    grid: "≈ 25 km Raster",
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

/// One model in the explainer: preview thumbnail, name, provider, a grid-size
/// capsule, and a one-liner on what the resolution means for the user.
struct WeatherModelCard: View {
    let name: String
    let provider: LocalizedStringKey
    let grid: LocalizedStringKey
    let imageName: String
    let summary: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: name)
                        .font(.subheadline.weight(.semibold))
                    Text(provider)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(grid)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.fill.secondary, in: Capsule())
            }
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
    }
}
