//
//  CatSprites.swift
//  Oscar°
//

import CoreMotion
import SwiftUI

struct FurnitureSprite: View {
    let kind: CatFurniture
    let variant: Int
    var swing = Angle.zero

    var body: some View {
        ZStack {
            Image(kind.image(variant))
                .interpolation(.none)
            if kind == .post {
                Image("cat_post_swing_\(variant)")
                    .interpolation(.none)
                    .rotationEffect(swing, anchor: UnitPoint(x: 0.5, y: 3 / kind.pixels.height))
            }
        }
    }
}

struct FurnitureFan: View {
    var body: some View {
        ZStack {
            FurnitureSprite(kind: .post, variant: 0)
                .scaleEffect(0.42)
                .offset(y: -3)
            FurnitureSprite(kind: .bed, variant: 0)
                .scaleEffect(0.42)
                .rotationEffect(.degrees(-10), anchor: .bottom)
                .offset(x: -7, y: 7)
            FurnitureSprite(kind: .bowl, variant: 0)
                .scaleEffect(0.75)
                .rotationEffect(.degrees(12), anchor: .bottom)
                .offset(x: 10, y: 7)
        }
        .frame(width: 44, height: 44)
    }
}

struct FurnitureIcon: View {
    let kind: CatFurniture
    let variant: Int

    var body: some View {
        let fit = min(34 / kind.pixels.width, 34 / kind.pixels.height)
        let scale = fit >= 1 ? fit.rounded(.down) : fit
        FurnitureSprite(kind: kind, variant: variant)
            .scaleEffect(scale)
            .frame(width: kind.pixels.width * scale, height: kind.pixels.height * scale)
    }
}

struct CatBubble<Content: View>: View {
    let tailOnRight: Bool
    @ViewBuilder let content: Content
    @State private var shown = false

    var body: some View {
        content
            .padding(.horizontal, 5)
            .padding(.top, 4)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity)
            .background {
                Image("cat_bubble_small")
                    .resizable(capInsets: EdgeInsets(top: 3, leading: 3, bottom: 5, trailing: 9), resizingMode: .stretch)
                    .interpolation(.none)
                    .scaleEffect(x: tailOnRight ? 1 : -1)
            }
            .scaleEffect(shown ? 1 : 0.3, anchor: tailOnRight ? .bottomTrailing : .bottomLeading)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(.bouncy) { shown = true } }
    }
}

struct CatItemIcon: View {
    let kind: CatItemKind
    let scale: CGFloat

    var body: some View {
        PixelSprite(
            sheet: kind.sheet,
            frames: kind.frames,
            frame: 0,
            size: CGSize(width: kind.pixels.width * scale, height: kind.pixels.height * scale)
        )
    }
}

struct PixelSprite: View {
    let sheet: String
    let frames: Int
    let frame: Int
    let size: CGSize
    var flipped = false

    var body: some View {
        Image(sheet)
            .resizable()
            .interpolation(.none)
            .frame(width: size.width * CGFloat(frames), height: size.height)
            .offset(x: -size.width * CGFloat(frame))
            .frame(width: size.width, height: size.height, alignment: .leading)
            .clipped()
            .scaleEffect(x: flipped ? -1 : 1)
    }
}

extension CatNeeds.Mood {
    var label: LocalizedStringResource {
        switch self {
        case .sleepy: "müde"
        case .hungry: "hungrig"
        case .bored: "gelangweilt"
        case .happy: "zufrieden"
        }
    }
}
