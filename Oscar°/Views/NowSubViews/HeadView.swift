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
                .lineSpacing(10)
                .foregroundColor(Color(UIColor.label))
            Spacer()
        }
        .onTapGesture {
            UIApplication.shared.playHapticFeedback()
            isLocationSheetPresented.toggle()
        }
        .sheet(isPresented: $isLocationSheetPresented) {
            SearchCityView()
        }
        .padding(.bottom, 35)
        .padding(.leading, -20)
        .padding(.top)
        
        VStack {
            VStack {
                Spacer()
                Text(roundTemperatureString(temperature: weather.forecast.current!.temperature))
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
        .scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.8)
                .scaleEffect(phase.isIdentity ? 1 : 0.99)
                .blur(radius: phase.isIdentity ? 0 : 0.5)
        }
    }
}
