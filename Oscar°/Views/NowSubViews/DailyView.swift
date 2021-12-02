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
            .foregroundColor(.white.opacity(0.8))
            .shadow(color: .white, radius: 40)
            .padding([.leading, .top, .bottom])
        HStack {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(weather?.daily! ?? [], id: \.self) { day in
                    Text(day.getWeekDay())
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.leading)
            Spacer()
            VStack(spacing: 5) {
                ForEach(weather?.daily! ?? [], id: \.self) { day in
                    Image(day.getIconString())
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                }
            }
            VStack(alignment: .leading, spacing: 21) {
                ForEach(weather?.daily! ?? [], id: \.self) { day in
                    Text(day.getFormattedPop() + " %")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 14) {
                ForEach(weather?.daily! ?? [], id: \.self) { day in
                    Text("\(day.temp.max, specifier: "%.0f")")
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 14) {
                ForEach(weather?.daily! ?? [], id: \.self) { day in
                    Text("\(day.temp.min, specifier: "%.0f")")
                        .fontWeight(.light)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color("gradientBlueDark-7").opacity(0.3))
        .cornerRadius(10)
        .font(.system(size: 18))
        .padding([.leading, .trailing])
    }
}
