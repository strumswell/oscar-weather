//
//  RainView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.
//

import SwiftUI
import Charts

struct RainView: View {
    @Binding var rain: RainRadarForecast?
    var body: some View {
        if ((rain?.getMaxPreci() ?? 0.0) > 0) {
            Text("Radar")
                .font(.system(size: 20))
                .bold()
                .foregroundColor(Color(UIColor.label))
                .padding([.leading, .top])
            
                HStack {
                    VStack {
                        Text("\(rain?.getMaxPreci() ?? 1, specifier: "%.1f") mm/h")
                            .font(.footnote)
                            .foregroundColor(Color(UIColor.label))
                        Spacer()
                        Text("\((rain?.getMaxPreci() ?? 1) / 2, specifier: "%.1f") mm/h")
                            .font(.footnote)
                            .foregroundColor(Color(UIColor.label))
                        Spacer()
                        Text("0 mm/h")
                            .font(.footnote)
                            .foregroundColor(Color(UIColor.label))
                        Text("")
                            .font(.footnote)
                            .foregroundColor(Color(UIColor.label))
                    }
                    VStack {
                        if ((rain?.getMaxPreci() ?? 1) <= 1) {
                            Chart(data: rain?.data.map{$0.mmh} ?? [])
                                .chartStyle(
                                    AreaChartStyle(.quadCurve, fill:
                                        LinearGradient(gradient: .init(colors: [Color.blue, Color.blue.opacity(0.5)]), startPoint: .top, endPoint: .bottom)
                                    )
                                )
                        } else if ((rain?.data.count ?? 0) > 0) {
                            Chart(data: rain?.data.map{$0.mmh / (rain?.getMaxPreci() ?? 1.0)} ?? [])
                                .chartStyle(
                                    AreaChartStyle(.quadCurve, fill:
                                        LinearGradient(gradient: .init(colors: [Color.blue, Color.blue.opacity(0.5)]), startPoint: .top, endPoint: .bottom)
                                    )
                                )
                        }
                        HStack() {
                            Text("\(rain?.getStartTime() ?? "")")
                                .font(.footnote)
                                .foregroundColor(Color(UIColor.label))
                            Spacer()
                            if (rain?.data.count ?? 0 > 1) {
                                Text("\(rain?.getMidTime() ?? "")")
                                    .font(.footnote)
                                    .foregroundColor(Color(UIColor.label))
                                Spacer()
                            }
                            Text("\(rain?.getEndTime() ?? "")")
                                .font(.footnote)
                                .foregroundColor(Color(UIColor.label))
                        }
                    }
                
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(Color(UIColor.secondarySystemFill))
            .cornerRadius(10)
            .font(.system(size: 18))
            .padding([.leading, .trailing, .bottom])
            .frame(height: 165)
        }
    }
}
