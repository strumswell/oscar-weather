//
//  ToastBanner.swift
//  Oscar°
//

import SwiftUI

struct ToastBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color(UIColor.label))
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1) }
            .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
            .accessibilityElement()
            .accessibilityLabel(Text(message))
    }
}
