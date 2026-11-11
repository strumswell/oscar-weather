//
//  MemberCardGlow.swift
//  Oscar°
//

import SwiftUI

extension MemberTier {
    var accent: Color {
        switch self {
        case .member: Color(hex: 0x6C9DDD)
        case .supporter: Color(hex: 0xF49A5A)
        case .founder, .founderSupporter: Color(hex: 0xB69BFF)
        case .atmosphere: Color(hex: 0x3D9BFF)
        }
    }
}

struct MemberCardGlow: View {
    let style: MemberTier

    var body: some View {
        RadialGradient(colors: [style.accent.opacity(0.32), .clear], center: .top, startRadius: 0, endRadius: 460)
            .ignoresSafeArea()
            .animation(.smooth, value: style)
    }
}
