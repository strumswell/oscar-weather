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
        LazyVStack {
            
            // MARK: Selected Location
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.7))
                    if (now.placemark?.location?.coordinate.latitude == 52.01 && now.placemark?.location?.coordinate.longitude == 10.77) {
                        Text("Hessen")
                            .font(.title2)
                            .fontWeight(.bold)
                            .lineSpacing(/*@START_MENU_TOKEN@*/10.0/*@END_MENU_TOKEN@*/)
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        Text(now.placemark?.locality ?? "Lade...")
                            .font(.title2)
                            .fontWeight(.bold)
                            .lineSpacing(/*@START_MENU_TOKEN@*/10.0/*@END_MENU_TOKEN@*/)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .onTapGesture {
                    isLocationSheetPresented.toggle()
                    UIApplication.shared.playHapticFeedback()
                }
                .sheet(isPresented: $isLocationSheetPresented) {
                    SearchView(searchModel: searchModel, now: now, cities: $now.cs.cities)
                }
                .frame(width: 700)
                .padding(.leading, -20)
                
                // MARK: Weather Alert
                if (now.weather?.alerts != nil) {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .resizable()
                            .frame(width: 15, height: 15)
                        Text(now.weather?.alerts?.first!.getFormattedEvent() ?? "...")
                            .font(.caption)
                            .bold()
                    }
                    //.frame(width: 110, height: 15)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.5))
                    .cornerRadius(25)
                    //.padding(.top)
                }
            }
            .padding(.bottom, 40)

            
            // MARK: Current Condition Symbol
            Image(now.weather?.current!.getIconString() ?? "")
                .resizable()
                .scaledToFit()
                .frame(width: 175, height: 175)
                .padding(.bottom, -10)
                    
            // MARK: Current Temperature
            Text("\(now.weather?.current!.temp ?? 0.0, specifier: "%.0f")°")
                .bold()
                .gradientForeground(colors: [.gray, .white])
                .font(.system(size: 70))
        }
        .padding(.top, 80)
        .padding(.bottom, 100)
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
