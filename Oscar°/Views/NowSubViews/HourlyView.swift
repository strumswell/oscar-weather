//
//  HourlyView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.
//

import SwiftUI
import Charts

struct HourlyView: View {
    @Binding var weather: OpenMeteoResponse?
    @Environment(Weather.self) private var weather2: Weather

    var body: some View {
        Text("Stündlich")
            .font(.title3)
            .bold()
            .foregroundColor(Color(UIColor.label))
            .padding(.leading)
            .padding(.bottom, -10)
            .padding(.top)
        
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(((weather?.getCurrentHourPos() ?? 0) ... ((weather?.getHourlySize() ?? 0) >= 60 ? 60 : (weather?.getHourlySize() ?? 10))), id: \.self) { hour in
                    VStack {
                        Text((weather?.getHourString(pos: hour) ?? "") + " Uhr")
                            .foregroundColor(Color(UIColor.label))
                            .bold()
                        Text("\(weather?.getHourPrec(pos: hour) ?? 0, specifier: "%.1f") mm")
                            .font(.footnote)
                            .foregroundColor(Color(UIColor.label))
                            .padding(.top, 3)
                        Text("\(weather?.getHourPrecProbability(pos: hour) ?? 0) %")
                            .font(.footnote)
                            .foregroundColor(Color(UIColor.secondaryLabel))
                        Image(weather?.getHourIcon(pos: hour) ?? "")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 35, height: 35)
                        Text(weather?.getHourTemp(pos: hour) ?? "")
                            .foregroundColor(Color(UIColor.label))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.3))
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
