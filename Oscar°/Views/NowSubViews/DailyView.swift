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
        Text("10-Tage")
            .font(.title3)
            .bold()
            .foregroundColor(Color(UIColor.label))
            .padding([.leading, .top, .bottom])
        HStack {
            
            VStack(alignment: .leading, spacing: 20) {
                ForEach(0...9, id: \.self) { dayPos in
                    Text(weather?.getWeekDay(timestamp: weather?.daily.time[dayPos] ?? 0.0) ?? "")
                        .foregroundColor(Color(UIColor.label))
                }
            }
            .padding(.leading)
            Spacer()
            VStack(spacing: 11) {
                ForEach(0...9, id: \.self) { dayPos in
                    Image(weather?.daily.getWeatherIcon(pos: dayPos) ?? "")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                }
            }
            VStack(alignment: .leading, spacing: 13) {
                ForEach(0...9, id: \.self) { dayPos in
                    VStack {
                        Text("\(weather?.daily.precipitationSum[dayPos] ?? 0, specifier: "%.1f") mm")
                            .font(.caption)
                            .foregroundColor(Color(UIColor.label))
                        Text("\(weather?.daily.precipitationProbabilityMax[dayPos] ?? 0) %")
                            .font(.caption)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 20) {
                ForEach(0...9, id: \.self) { dayPos in
                    Text(weather?.daily.getRoundedMaxTemp(pos: dayPos) ?? "")
                        .fontWeight(.semibold)
                        .foregroundColor(Color(UIColor.label))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 20) {
                ForEach(0...9, id: \.self) { dayPos in
                    Text(weather?.daily.getRoundedMinTemp(pos: dayPos) ?? "")
                        .fontWeight(.light)
                        .foregroundColor(Color(UIColor.label))
                }
            }
            .padding(.trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemBackground).opacity(0.3))
        .cornerRadius(10)
        .font(.system(size: 18))
        .padding([.leading, .trailing])
    }
}
