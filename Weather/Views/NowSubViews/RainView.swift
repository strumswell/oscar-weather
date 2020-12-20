//
//  RainView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.
//

import SwiftUI

struct RainView: View {
    @Binding var weather: WeatherResponse?
    var body: some View {
        Text("Regen")
            .font(.system(size: 20))
            .bold()
            .padding([.leading, .top])
        
        HStack {
            VStack(alignment: .trailing) {
                Text("\(weather?.getMaxPreci() ?? 0.0, specifier: "%.1f") mm")
                    .font(.caption2)
                Spacer()
                Text("\(weather?.getMaxPreci() ?? 0.0 / 2, specifier: "%.1f") mm")
                    .font(.caption2)
                Spacer()
                Text("0.0 mm")
                    .font(.caption2)
            }
            .padding(.leading)
            .frame(height: 50)
            .padding(.bottom, 50)

            
            VStack() {
                HStack(alignment: .bottom, spacing: 4) {
                    Capsule()
                        .opacity(0)
                        .frame(width: 1, height: 50)
                    ForEach(weather?.minutely! ?? [], id: \.self) { n in
                        Capsule()
                            .fill(Color.white)
                            .frame(width: 1, height: CGFloat(n.getHeight(maxHeight: 50, maxPreci: weather?.getMaxPreci() ?? 0.0)) + 1)
                    }
                }
                .frame(height: 50)
                
                HStack() {
                    Text("\(weather?.minutely?.first?.getTimeString() ?? "")")
                        .font(.footnote)
                    Spacer()
                    if (weather?.minutely!.count ?? 0 > 1) {
                        Text("\(weather?.minutely?[30].getTimeString() ?? "")")
                            .font(.footnote)
                        Spacer()
                    }
                    Text("\(weather?.minutely?.last?.getTimeString() ?? "")")
                        .font(.footnote)
                }
                Spacer()
            }
            .padding([.trailing])
        }
        .frame(height: 100)
    }
}
