//
//  NowView.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.
//  Weather icons by Rasmus Nielsen https://www.iconfinder.com/iconsets/weatherful

import SwiftUI

struct NowView: View {
    @ObservedObject var nowViewModel: NowViewModel = NowViewModel()

    init() {
        UITabBar.appearance().backgroundColor = .clear
    }
    
    var body: some View {
        VStack {
            ScrollView(.vertical, showsIndicators: false) {
                RefreshView(coordinateSpace: .named("RefreshView"), nowViewModel: nowViewModel)
                HeadView(weather: $nowViewModel.weather, placemark: $nowViewModel.placemark)
                    
                VStack(alignment: .leading) {
                    Spacer().frame(height: 20)
                    RainView(weather: $nowViewModel.weather)
                    HourlyView(weather: $nowViewModel.weather)
                    DailyView(weather: $nowViewModel.weather)
                    RadarView(location: $nowViewModel.coordinates, radarMetadata: $nowViewModel.currentRadarMetadata)
                }
                .background(Color("gradientBlueLight"))
                .cornerRadius(25)
            }
            .coordinateSpace(name: "RefreshView")
        }
        .padding(.top)
        .background(LinearGradient(gradient: Gradient(colors: [.black, Color("gradientBlueLight")]), startPoint: .topTrailing, endPoint: .bottom))
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            nowViewModel.update()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            nowViewModel.update()
        }
    }
}

struct NowView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NowView()
                .preferredColorScheme(.dark)
        }
    }
}
