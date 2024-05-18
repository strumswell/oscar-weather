//
//  MemoryView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 05.05.24.
//

import SwiftUI

struct MemoryView: View {
    var body: some View {
        ZStack {
            MemoryStars()
            VStack {
                ImageCircleView()
                    .padding(30)
                Spacer()
                VStack {
                    Text("Oscar°")
                        .font(.system(size: 50))
                        .fontWeight(.medium)
                        .padding(.bottom, 1)
                    Text("... wurde in liebevoller Erinnerung an diejenigen entwickelt, die nicht mehr unter uns sind. In unseren Herzen und Gedanken bleiben sie jedoch für immer lebendig.")
                        .font(.body)
                        .fontWeight(.regular)
                        .multilineTextAlignment(.center)
                        .padding([.leading, .trailing], 50)
                }
                .foregroundColor(.white.opacity(0.9))
                .shadow(radius: 15)
                .padding(.bottom, 60)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [.midnightStart, .midnightEnd], startPoint: .top, endPoint: .bottom))
    }
}

#Preview {
    MemoryView()
}

struct ImageCircleView: View {
    let imageNames = ["oscar", "reinhard", "urselwerner", "daniela"]

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let radius = diameter / 3.4

            ForEach(0..<imageNames.count, id: \.self) { index in
                Image(imageNames[index])
                    .resizable()
                    .scaledToFill()
                    .grayscale(1.0)
                    .opacity(0.95)
                    .frame(width: diameter / 2.2, height: diameter / 2.2)
                    .clipShape(Circle())
                    .position(x: geometry.size.width / 2 + radius * cos(CGFloat(index) * 2 * .pi / CGFloat(imageNames.count)),
                              y: geometry.size.height / 2 + radius * sin(CGFloat(index) * 2 * .pi / CGFloat(imageNames.count)))
                    .shadow(color: .black.opacity(0.4), radius: 20)
            }
        }
    }
}

struct MemoryStars: View {
    @State var starField = StarField()
    @State var meteorShower = MeteorShower()

    var body: some View {
        TimelineView(.animation) { timeline in
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
        }
        .mask(
            LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom)
        )
        .ignoresSafeArea()
    }
}
