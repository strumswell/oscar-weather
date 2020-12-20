//
//  NowView.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.
//  Weather icons by Rasmus Nielsen https://www.iconfinder.com/iconsets/weatherful

import SwiftUI
import MapKit


struct NowView: View {
    @ObservedObject var nowViewModel: NowViewModel = NowViewModel()
    
    init() {
        UITabBar.appearance().backgroundColor = .clear
    }
    
    var body: some View {
        VStack {
            ScrollView(.vertical, showsIndicators: false) {
                HeadView(weather: $nowViewModel.weather, placemark: $nowViewModel.placemark)
                VStack(alignment: .leading) {
                    RainView(weather: $nowViewModel.weather)
                    HourlyView(weather: $nowViewModel.weather)
                    DailyView(weather: $nowViewModel.weather)
                }
                .padding(.bottom, 80)
            }
        }
        .padding(.top)
        .background(LinearGradient(gradient: Gradient(colors: [Color("gradientBlueDark"), Color("gradientBlueLight")]), startPoint: .top, endPoint: .bottom))
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            nowViewModel.fetchCurrentCoordinates()
            nowViewModel.fetchCurrentPlacemark()
            nowViewModel.fetchCurrentWeather()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            nowViewModel.fetchCurrentCoordinates()
            nowViewModel.fetchCurrentPlacemark()
            nowViewModel.fetchCurrentWeather()
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
