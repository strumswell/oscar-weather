//
//  HeadView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.
//

import SwiftUI

struct HeadView: View {
    @Binding var weather: WeatherResponse
    var body: some View {
        VStack {
            Text("Brandenburg an der Havel")
                .font(.title)
                .fontWeight(.regular)
                .padding(.bottom)
            HStack(alignment: .center) {
                Image(weather.current!.getIconString())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                Text("\(weather.current!.temp, specifier: "%.0f")°")
                    .font(.system(size: 90))
                    .fontWeight(.regular)
            }
            .padding(.bottom)
            Text("\(weather.current?.weatherInfo() ?? "")")
                .font(.title3)
                .padding(.bottom)
        }
        .padding(.top, 100)
        .padding(.bottom, 50)
    }
}
