//
//  HeadView.swift
//  Weather
//
//  Created by Philipp Bolte on 24.10.20.

import SwiftUI
import CoreLocation
import Charts

struct HeadView: View {
    @ObservedObject var searchModel: SearchViewModel = SearchViewModel()
    @ObservedObject var now: NowViewModel
    @State private var isLocationSheetPresented = false
    
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location
    
    var body: some View {
        HStack {
            Spacer()
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color(UIColor.label))
            Text(location.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineSpacing(/*@START_MENU_TOKEN@*/10.0/*@END_MENU_TOKEN@*/)
                    .foregroundColor(Color(UIColor.label))
            Spacer()
        }
        .onTapGesture {
            UIApplication.shared.playHapticFeedback()
            isLocationSheetPresented.toggle()
        }
        .sheet(isPresented: $isLocationSheetPresented) {
            SearchView(searchModel: searchModel, now: now, cities: $now.cs.cities)
        }
        .padding(.bottom, 40)
        .padding(.leading, -20)
        .padding(.top)
        
        LazyVStack {
            VStack {
                Spacer()
                // MARK: Current Temperature
                Text(String(weather.forecast.current!.temperature.rounded()).replacingOccurrences(of: ".0", with: "") + "°")
                    .foregroundColor(Color(UIColor.label))
                    .font(.system(size: 120))
            }
            .padding(.bottom, 150)

            HStack {
                Spacer()
                Image(systemName: "cloud")
                    .frame(width: 30, height: 30)
                    .foregroundColor(Color(UIColor.label))
                Text("\(weather.forecast.current!.cloudcover, specifier: "%.0f") %")
                    .foregroundColor(Color(UIColor.label))
                Image(systemName: "wind")
                    .frame(width: 30, height: 30)
                    .foregroundColor(Color(UIColor.label))
                Text("\(weather.forecast.current!.windspeed, specifier: "%.1f") km/h")
                    .foregroundColor(Color(UIColor.label))
                Image(systemName: "location")
                    .frame(width: 30, height: 30)
                    .foregroundColor(Color(UIColor.label))
                Text("\(weather.forecast.current!.getWindDirection())")
                Spacer()
            }
            .padding(.bottom)

            if (weather.alerts.count > 0) {
                AlertView()
            }
        }
    }
}
