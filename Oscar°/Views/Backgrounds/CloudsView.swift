//
//  CloudsView.swift
//  Weather
//
//  Created by Paul Hudson on 12/11/2021.
//

import SwiftUI

struct CloudsView: View {
    @State var isShown = false
    var cloudGroup: CloudGroup
    let topTint: Color
    let bottomTint: Color
    let paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { timeline in
            if isShown {
                Canvas { context, size in
                    cloudGroup.update(date: timeline.date)
                    context.opacity = cloudGroup.opacity
                    
                    let usedImageNumbers = Set(cloudGroup.clouds.map(\.imageNumber))
                    let resolvedImages = Dictionary(
                        uniqueKeysWithValues: usedImageNumbers.map { i -> (Int, GraphicsContext.ResolvedImage) in
                        let sourceImage = Image("cloud\(i)")
                        var resolved = context.resolve(sourceImage)
                        
                        resolved.shading = .linearGradient(
                            Gradient(colors: [topTint, bottomTint]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: 0, y: resolved.size.height)
                        )
                        
                            return (i, resolved)
                        }
                    )
                    
                    for cloud in cloudGroup.clouds {
                        context.translateBy(x: cloud.position.x, y: cloud.position.y)
                        context.scaleBy(x: cloud.scale, y: cloud.scale)
                        if let image = resolvedImages[cloud.imageNumber] {
                            context.draw(image, at: .zero, anchor: .topLeading)
                        }
                        context.transform = .identity
                    }
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0)) {
                self.isShown = true
            }
        }
    }

    init(
        thickness: Cloud.Thickness,
        topTint: Color,
        bottomTint: Color,
        paused: Bool = false
    ) {
        cloudGroup = CloudGroup(thickness: thickness)
        self.topTint = topTint
        self.bottomTint = bottomTint
        self.paused = paused
    }
}

struct CloudsView_Previews: PreviewProvider {
    static var previews: some View {
        CloudsView(thickness: .regular, topTint: .white, bottomTint: .white)
            .background(.blue)
    }
}
