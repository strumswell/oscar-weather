//
//  DailyView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.
//

import SwiftUI

struct DailyView: View {
    @Binding var weather: WeatherResponse?
    var body: some View {
        Text("7-Tage")
            .font(.system(size: 20))
            .bold()
            .padding([.leading, .top])
        HStack {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(weather?.daily! ?? [], id: \.self) { day in
                    Text(day.getWeekDay())
                }
            }
            Spacer()
            VStack(spacing: 0.5) {
                ForEach(weather?.daily! ?? [], id: \.self) { day in
                    Image(day.getIconString())
                        .resizable()
                        .scaledToFit()
                        .frame(width: 35, height: 35)
                }
            }
            VStack(alignment: .leading, spacing: 21) {
                ForEach(weather?.daily! ?? [], id: \.self) { day in
                    Text(day.getFormattedPop() + " %")
                        .font(.caption)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 14) {
                ForEach(weather?.daily! ?? [], id: \.self) { day in
                    Text("\(day.temp.max, specifier: "%.0f")")
                        .fontWeight(.semibold)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 14) {
                ForEach(weather?.daily! ?? [], id: \.self) { day in
                    Text("\(day.temp.min, specifier: "%.0f")")
                        .fontWeight(.light)
                }
            }
        }
        .font(.system(size: 18))
        .padding([.leading, .trailing, .bottom])
    }
}

struct DailyView_Previews: PreviewProvider {
    static var previews: some View {
        /*@START_MENU_TOKEN@*/Text("Hello, World!")/*@END_MENU_TOKEN@*/
    }
}
