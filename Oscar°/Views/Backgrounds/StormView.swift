//
//  StormView.swift
//  Weather
//
//  Created by Paul Hudson on 03/02/2022.
//

import SwiftUI

struct StormView: View {
    @State private var isShown = false
    let storm: Storm

    var body: some View {
        TimelineView(.animation) { timeline in
            if isShown {
                Canvas { context, size in
                    storm.update(date: timeline.date, size: size)
                    
                    for drop in storm.drops {
                        var contextCopy = context
                        
                        let xPos = drop.x * size.width
                        let yPos = drop.y * size.height
                        
                        contextCopy.opacity = drop.opacity
                        contextCopy.translateBy(x: xPos, y: yPos)
                        contextCopy.rotate(by: drop.direction + drop.rotation)
                        contextCopy.scaleBy(x: drop.xScale, y: drop.yScale)
                        contextCopy.draw(storm.image, at: .zero)
                    }
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0)) {
                self.isShown = true
            }
        }
    }

    init(type: Storm.Contents, direction: Angle, strength: Int) {
        storm = Storm(type: type, direction: direction, strength: strength)
    }
}

struct StormView_Previews: PreviewProvider {
    static var previews: some View {
        StormView(type: .rain, direction: .zero, strength: 200)
    }
}
