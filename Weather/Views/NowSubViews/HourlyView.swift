//
//  HourlyView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.
//

import SwiftUI

struct HourlyView: View {
    @Binding var weather: WeatherResponse?
    
    var body: some View {
        Text("Stündlich")
            .font(.system(size: 20))
            .bold()
            .padding(.leading)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 30) {
                ForEach(weather?.hourly! ?? [], id: \.self) { hour in
                    VStack {
                        Text(hour.getHourString() + " Uhr")
                        Text(hour.getFormattedPop() + " %")
                            .font(.footnote)
                            .padding(.top, 3)
                            .padding(.bottom, -15)
                        Image(hour.getIconString())
                            .resizable()
                            .scaledToFit()
                            .frame(width: 35, height: 35)
                        Text("\(hour.temp, specifier: "%.0f")°")
                    }
                }
            }
            .font(.system(size: 18))
            .padding(.leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }
}
