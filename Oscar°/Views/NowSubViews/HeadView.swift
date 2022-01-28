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
    @State private var isAlterSheetPresented = false
    
    var body: some View {
        HStack {
            Spacer()
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
            Spacer()
        }
        .onTapGesture {
            UIApplication.shared.playHapticFeedback()
            isLocationSheetPresented.toggle()
        }
        .sheet(isPresented: $isLocationSheetPresented) {
            SearchView(searchModel: searchModel, now: now, cities: $now.cs.cities)
        }
        .padding(.bottom)
        .padding(.leading, -20)
        .padding(.top)
        
        LazyVStack {
            HStack {
                // MARK: Current Condition Symbol
                Image(now.weather?.current!.getIconString() ?? "")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .padding(.bottom, -10)
                        
                VStack {
                    Spacer()
                    // MARK: Current Temperature
                    Text("\(now.weather?.current!.temp ?? 0.0, specifier: "%.0f")°")
                        .bold()
                        .gradientForeground(colors: [.gray, .white])
                        .font(.system(size: 60))
                }

            }
            
            // MARK: Weather Alert
            if ((now.alerts?.count ?? 0) > 0) {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .resizable()
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 15, height: 15)
                    Text(now.alerts?.first?.description.localized.uppercased() ?? "...")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .bold()
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.7))
                .cornerRadius(25)
                .onTapGesture {
                    UIApplication.shared.playHapticFeedback()
                    isAlterSheetPresented.toggle()
                }
                .sheet(isPresented: $isAlterSheetPresented) {
                    AlertListView(alerts: $now.alerts)
                }
                .padding(.top, -10)
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
