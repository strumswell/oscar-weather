//
//  NowView.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.

import SwiftUI

struct NowView: View {
    @ObservedObject var nowViewModel: NowViewModel = NowViewModel()
    @State private var isLegalSheetPresented = false
    @State private var isMapSheetPresented = false
    
    var body: some View {
        ZStack {
            // MARK: Map Header
            VStack {
                ZStack {
                    RadarView(now: nowViewModel, radarMetadata: $nowViewModel.currentRadarMetadata, showLayerSettings: false)
                        .frame(height: 500)
                    Rectangle()
                        .frame(height: 500, alignment: .top)
                        .foregroundColor(.clear)
                        .background(LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.6), .clear]), startPoint: .top, endPoint: .center))
                }
                Spacer()
            }

            // MARK: Weather Sheet
            ScrollView(.vertical, showsIndicators: false) {
                RefreshView(coordinateSpace: .named("RefreshView"), nowViewModel: nowViewModel)
                
                // Proxy element to check for taps on map behind scroll view
                Rectangle()
                    .frame(height: 200)
                    .foregroundColor(Color.gray.opacity(0.0001)) // No on tap for .clear
                    .onTapGesture {
                        UIApplication.shared.playHapticFeedback()
                        isMapSheetPresented.toggle()
                    }
                    .sheet(isPresented: $isMapSheetPresented) {
                        MapDetailView(now: nowViewModel)
                    }
                
                VStack(alignment: .leading) {
                    Spacer().frame(height: 20)
                    HeadView(now: nowViewModel)
                    RainView(weather: $nowViewModel.weather)
                    HourlyView(weather: $nowViewModel.weather)
                    DailyView(weather: $nowViewModel.weather)
                    HStack {
                        Spacer()
                        Image(systemName: "info.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.gray.opacity(0.8))
                        Text("Rechtliche\nInformationen")
                            .foregroundColor(.gray.opacity(0.8))
                            .font(.system(size: 10))
                            .bold()
                        Spacer()
                    }
                    .padding(.top)
                    .padding(.bottom, 50)
                    .onTapGesture {
                        UIApplication.shared.playHapticFeedback()
                        isLegalSheetPresented.toggle()
                    }
                    .sheet(isPresented: $isLegalSheetPresented) {
                        LegalView()
                    }
                }
                .background(LinearGradient(gradient: Gradient(colors: [Color.black, Color("gradientBlueLight-4")]), startPoint: .bottom, endPoint: .top))
                .cornerRadius(25)
                .shadow(color: .black.opacity(0.5), radius: 25)
            }
            .coordinateSpace(name: "RefreshView")
        }
        .background(Color.black)
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            nowViewModel.update()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            nowViewModel.update() // Why again? onAppear does not seem to be enough --> bug in SwiftUI?
        }
        .onReceive(NotificationCenter.default.publisher(for:  Notification.Name("ChangedLocation"), object: nil)) { _ in
            nowViewModel.update() // GPS location has changed dramatically (2.5km)
        }
        .onReceive(NotificationCenter.default.publisher(for:  Notification.Name("CityToggle"), object: nil)) { _ in
            nowViewModel.update() // User selected city might have changed
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
