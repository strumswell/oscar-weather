//
//  StarsView.swift
//  Weather
//
//  Created by Paul Hudson on 09/01/2022.
//

import SwiftUI

struct StarsView: View {
    @State var isShown = false
    @State var starField = StarField()
    @State var meteorShower = MeteorShower()
    
    @Environment(Weather.self) private var weather: Weather
    
    let starStops: [Gradient.Stop] = [
        .init(color: .white, location: 0),
        .init(color: .white, location: 0.25),
        .init(color: .clear, location: 0.33),
        .init(color: .clear, location: 0.38),
        .init(color: .clear, location: 0.7),
        .init(color: .clear, location: 0.78),
        .init(color: .white, location: 0.82),
        .init(color: .white, location: 1)
    ]

    var starOpacity: Double {
        let color = starStops.interpolated(amount: weather.time)
        return color.getComponents().alpha
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            if starOpacity > 0.1 {
                Canvas { context, size in
                    let timeInterval = timeline.date.timeIntervalSince1970
                    starField.update(date: timeline.date)
                    meteorShower.update(date: timeline.date, size: size)
                    
                    let rightColors = [.clear, Color(red: 0.8, green: 1, blue: 1), .white]
                    let leftColors = Array(rightColors.reversed())
                    
                    for meteor in meteorShower.meteors {
                        var contextCopy = context
                        
                        if meteor.isMovingRight {
                            contextCopy.rotate(by: .degrees(10))
                            let path = Path(CGRect(x: meteor.x - meteor.length, y: meteor.y, width: meteor.length, height: 2))
                            contextCopy.fill(path, with: .linearGradient(.init(colors: rightColors), startPoint: CGPoint(x: meteor.x - meteor.length, y: 0), endPoint: CGPoint(x: meteor.x, y: 0)))
                        } else {
                            contextCopy.rotate(by: .degrees(-10))
                            let path = Path(CGRect(x: meteor.x, y: meteor.y, width: meteor.length, height: 2))
                            contextCopy.fill(path, with: .linearGradient(.init(colors: leftColors), startPoint: CGPoint(x: meteor.x, y: 0), endPoint: CGPoint(x: meteor.x + meteor.length, y: 0)))
                        }
                        
                        let glow = Path(ellipseIn: CGRect(x: meteor.x - 1, y: meteor.y - 1, width: 4, height: 4))
                        contextCopy.addFilter(.blur(radius: 1))
                        contextCopy.fill(glow, with: .color(white: 1))
                    }
                    
                    context.addFilter(.blur(radius: 0.3))
                    
                    for (index, star) in starField.stars.enumerated() {
                        let path = Path(ellipseIn: CGRect(x: star.x, y: star.y, width: star.size, height: star.size))
                        
                        if star.flickerInterval == 0 {
                            // flashing star
                            var flashLevel = sin(Double(index) + timeInterval * 4)
                            flashLevel = abs(flashLevel)
                            flashLevel /= 1.5
                            context.opacity = 0.5 + flashLevel
                        } else {
                            // blooming star
                            var flashLevel = sin(Double(index) + timeInterval)
                            flashLevel *= star.flickerInterval
                            flashLevel -= star.flickerInterval - 1
                            
                            if flashLevel > 0 {
                                var contextCopy = context
                                contextCopy.opacity = flashLevel
                                contextCopy.addFilter(.blur(radius: 3))
                                
                                contextCopy.fill(path, with: .color(white: 1))
                                contextCopy.fill(path, with: .color(white: 1))
                                contextCopy.fill(path, with: .color(white: 1))
                            }
                            
                            context.opacity = 1
                        }
                        
                        if index.isMultiple(of: 5) {
                            context.fill(path, with: .color(red: 1, green: 0.85, blue: 0.8))
                        } else {
                            context.fill(path, with: .color(white: 1))
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .opacity(starOpacity)
        .ignoresSafeArea()
        .mask(
            LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
        )
        .onAppear {
            withAnimation(.default) {
                self.isShown = true
            }
        }
    }
}

struct StarsView_Previews: PreviewProvider {
    static var previews: some View {
        StarsView()
    }
}
