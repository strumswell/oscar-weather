//
//  DailyView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.
//

import SwiftUI

struct DailyView: View {
    @Binding var weather: OpenMeteoResponse?

    var body: some View {
        Text("7-Tage")
            .font(.system(size: 20))
            .bold()
            .foregroundColor(Color(UIColor.label))
            .padding([.leading, .top, .bottom])
        HStack {
            
            VStack(alignment: .leading, spacing: 16) {
                ForEach(0...6, id: \.self) { dayPos in
                    Text(weather?.daily.getWeekDay(pos: dayPos) ?? "")
                        .foregroundColor(Color(UIColor.label))
                }
            }
            .padding(.leading)
            Spacer()
            VStack(spacing: 7) {
                ForEach(0...6, id: \.self) { dayPos in
                    Image(weather?.daily.getWeatherIcon(pos: dayPos) ?? "")
                        .resizable()
                        .scaledToFit()
                        .shadow(radius: 5)
                        .frame(width: 30, height: 30)
                }
            }
            VStack(alignment: .leading, spacing: 23.5) {
                ForEach(0...6, id: \.self) { dayPos in
                    Text("\(weather?.daily.precipitationSum[dayPos] ?? 0, specifier: "%.1f") mm")
                        .font(.caption)
                        .foregroundColor(Color(UIColor.label))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 16) {
                ForEach(0...6, id: \.self) { dayPos in
                    Text(weather?.daily.getRoundedMaxTemp(pos: dayPos) ?? "")
                        .fontWeight(.semibold)
                        .foregroundColor(Color(UIColor.label))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 16) {
                ForEach(0...6, id: \.self) { dayPos in
                    Text(weather?.daily.getRoundedMinTemp(pos: dayPos) ?? "")
                        .fontWeight(.light)
                        .foregroundColor(Color(UIColor.label))
                }
            }
            .padding(.trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemFill))
        .cornerRadius(10)
        .font(.system(size: 18))
        .padding([.leading, .trailing])
    }
}
