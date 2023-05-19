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
    
    var body: some View {
        HStack {
            Spacer()
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color(UIColor.label))
            Text(now.placemark?.locality ?? "Lade...")
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
                // MARK: Current Condition Symbol
                /**
                Image(now.weather?.getCurrentIcon() ?? "")
                    .resizable()
                    .scaledToFit()
                    .shadow(radius: 5)
                    .frame(width: 125, height: 125)
                    .padding(.bottom, -10)
                 */
                        
                VStack {
                    Spacer()
                    // MARK: Current Temperature
                    Text(now.weather?.currentWeather.getRoundedTempString() ?? "")
                        //.bold()
                        .foregroundColor(Color(UIColor.label))
                        //.font(.system(size: 60))
                        .font(.system(size: 120))
                }
            }
            .padding(.bottom, 150)

            HStack {
                Spacer()
                Image(systemName: "cloud")
                    .frame(width: 30, height: 30)
                    .foregroundColor(Color(UIColor.label))
                Text("\(now.weather?.getCurrentCloudCover() ?? 0, specifier: "%.0f") %")
                    .foregroundColor(Color(UIColor.label))
                Image(systemName: "wind")
                    .frame(width: 30, height: 30)
                    .foregroundColor(Color(UIColor.label))
                Text("\(now.weather?.currentWeather.windspeed ?? 0, specifier: "%.1f") km/h")
                    .foregroundColor(Color(UIColor.label))
                Image(systemName: "location")
                    .frame(width: 30, height: 30)
                    .foregroundColor(Color(UIColor.label))
                Text("\(now.weather?.currentWeather.getWindDirection() ?? "N/A")")
                Spacer()
            }
            .padding(.bottom)

            if ((now.alerts?.count ?? 0) > 0) {
                AlertView(alerts: $now.alerts)
            }
        }
    }
}

extension View {
    public func gradientForeground(colors: [Color]) -> some View {
        self.overlay(LinearGradient(gradient: .init(colors: colors),
                                    startPoint: .bottom,
                                    endPoint: .top))
            .mask(self)
    }
}
