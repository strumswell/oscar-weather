//
//  AttributionViews.swift
//  Oscar°
//
//  Shared building blocks for the source credits shown across the app.
//

import SwiftUI

/// Height-locked provider mark. The template logos (DWD, ECMWF, EUMETNET,
/// Oscar° Server) tint via the surrounding foregroundStyle; NOAA and
/// Open-Meteo carry their own artwork.
struct ProviderLogo: View {
    let asset: String
    var height: CGFloat = 14

    var body: some View {
        Image(decorative: asset)
            .resizable()
            .scaledToFit()
            .frame(height: height)
    }
}

/// "Powered by <Oscar° Server lockup>" credit line.
struct PoweredByOscarServer: View {
    var lockupHeight: CGFloat = 20

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: "Powered by")
                .font(.caption2)
            ProviderLogo(asset: "logo-oscar-server", height: lockupHeight)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Powered by Oscar Server"))
    }
}
