//
//  RainView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.
//

import SwiftUI
import Charts

struct RainView: View {
    @Binding var weather: WeatherResponse?
    var body: some View {
        if ((weather?.getMaxPreci() ?? 0.0) > 0.0) {
            Text("Regen")
                .font(.system(size: 20))
                .bold()
                .foregroundColor(.white.opacity(0.8))
                .shadow(color: .white, radius: 40)
                .padding([.leading, .top])
            
            VStack {
                HStack {
                    VStack {
                        Text("\(weather?.getMaxPreciLabel() ?? 1.0, specifier: "%.1f") mm/h")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\((weather?.getMaxPreciLabel() ?? 1.0) / 2, specifier: "%.1f") mm/h")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("0 mm/h")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.7))
                        Text("")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    VStack {
                        if ((weather?.getMaxPreci() ?? 1.0) <= 1.0) {
                            Chart(data: weather?.minutely!.map{$0.precipitation} ?? [])
                                .chartStyle(
                                    AreaChartStyle(.quadCurve, fill:
                                                    LinearGradient(gradient: .init(colors: [Color.blue.opacity(0.6), Color.blue.opacity(0.2)]), startPoint: .top, endPoint: .bottom)
                                    )
                                )
                        } else {
                            Chart(data: weather?.minutely!.map{$0.precipitation / (weather?.getMaxPreci() ?? 1.0)} ?? [])
                                .chartStyle(
                                    AreaChartStyle(.quadCurve, fill:
                                                    LinearGradient(gradient: .init(colors: [Color.blue.opacity(0.6), Color.blue.opacity(0.2)]), startPoint: .top, endPoint: .bottom)
                                    )
                                )
                        }
                        HStack() {
                            Text("\(weather?.minutely?.first?.getTimeString() ?? "")")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.7))
                            Spacer()
                            if (weather?.minutely!.count ?? 0 > 1) {
                                Text("\(weather?.minutely?[30].getTimeString() ?? "")")
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.7))
                                Spacer()
                            }
                            Text("\(weather?.minutely?.last?.getTimeString() ?? "")")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color("gradientBlueDark-7").opacity(0.3))
            .cornerRadius(10)
            .font(.system(size: 18))
            .padding([.leading, .trailing, .bottom])
            .frame(height: 165)
        }
    }
}
