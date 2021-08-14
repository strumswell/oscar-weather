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
        LazyVStack {
            Text(placemark?.locality ?? "...")
                .font(.title2)
                .fontWeight(.bold)
                .lineSpacing(/*@START_MENU_TOKEN@*/10.0/*@END_MENU_TOKEN@*/)
                .foregroundColor(.white)
                .padding(.bottom, 40)
                .gradientForeground(colors: [Color("gradientBlueDark"), .white])

            Image(weather?.current!.getIconString() ?? "")
                .resizable()
                .scaledToFit()
                .frame(width: 175, height: 175)
                .padding(.bottom, -10)
            
            Text("\(weather?.current!.temp ?? 0.0, specifier: "%.0f")°")
                .bold()
                .gradientForeground(colors: [Color("gradientBlueDark"), .white])
                .font(.system(size: 90))
        }
        .padding(.top, 80)
        .padding(.bottom, 100)
    }
}

extension View {
    public func gradientForeground(colors: [Color]) -> some View {
        self.overlay(LinearGradient(gradient: .init(colors: colors),
                                    startPoint: .bottom,
                                    endPoint: .top))
            .mask(self)
    }
}
