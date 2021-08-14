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
            .foregroundColor(.white.opacity(0.8))
            .shadow(color: .white, radius: 40)
            .padding(.leading)
            .padding(.bottom, -10)
        
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 15) {
                ForEach(weather?.hourly! ?? [], id: \.self) { hour in
                    VStack {
                        Text(hour.getHourString() + " Uhr")
                            .foregroundColor(.white.opacity(0.7))
                            .bold()
                        Text(hour.getFormattedPop() + " %")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.top, 3)
                            .padding(.bottom, -10)
                        Image(hour.getIconString())
                            .resizable()
                            .scaledToFit()
                            .frame(width: 35, height: 35)
                        Text("\(hour.temp, specifier: "%.0f")°")
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(10)
                }
                .padding(.vertical, 20)

            }
            .font(.system(size: 18))
            .padding(.leading)
        }
        .frame(maxWidth: .infinity)
    }
}
