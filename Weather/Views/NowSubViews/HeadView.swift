//
//  HeadView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.

import SwiftUI
import CoreLocation

struct HeadView: View {
    @Binding var weather: WeatherResponse?
    @Binding var placemark: CLPlacemark?
    
    var body: some View {
        VStack {
            Text(placemark?.locality ?? "...")
                .font(.title)
                .fontWeight(.regular)
                .padding(.bottom)
            HStack(alignment: .center) {
                Image(weather?.current!.getIconString() ?? "")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                Text("\(weather?.current!.temp ?? 0.0, specifier: "%.0f")°")
                    .font(.system(size: 90))
                    .fontWeight(.regular)
            }
            .padding(.bottom)
            Text("\(weather?.current!.weatherInfo() ?? "")")
                .font(.title3)
                .padding(.bottom)
        }
        .padding(.top, 90)
        .padding(.bottom, 50)
    }
}
