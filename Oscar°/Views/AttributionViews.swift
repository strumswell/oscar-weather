//
//  AttributionViews.swift
//  Oscar°
//
//  Shared building blocks for the source credits shown across the app.
//

import SwiftUI

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
