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

    var body: some View {
        TimelineView(.animation) { timeline in
            if isShown {
                Canvas { context, size in
                    cloudGroup.update(date: timeline.date)
                    context.opacity = cloudGroup.opacity
                    
                    let resolvedImages = (0..<8).map { i -> GraphicsContext.ResolvedImage in
                        let sourceImage = Image("cloud\(i)")
                        var resolved = context.resolve(sourceImage)
                        
                        resolved.shading = .linearGradient(
                            Gradient(colors: [topTint, bottomTint]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: 0, y: resolved.size.height)
                        )
                        
                        return resolved
                    }
                    
                    for cloud in cloudGroup.clouds {
                        context.translateBy(x: cloud.position.x, y: cloud.position.y)
                        context.scaleBy(x: cloud.scale, y: cloud.scale)
                        context.draw(resolvedImages[cloud.imageNumber], at: .zero, anchor: .topLeading)
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

    init(thickness: Cloud.Thickness, topTint: Color, bottomTint: Color) {
        cloudGroup = CloudGroup(thickness: thickness)
        self.topTint = topTint
        self.bottomTint = bottomTint
    }
}

struct CloudsView_Previews: PreviewProvider {
    static var previews: some View {
        CloudsView(thickness: .regular, topTint: .white, bottomTint: .white)
            .background(.blue)
    }
}
