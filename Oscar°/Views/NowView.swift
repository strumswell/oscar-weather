//
//  NowView.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.

import SwiftUI
import SPIndicator

struct NowView: View {
    @ObservedObject var nowViewModel: NowViewModel = NowViewModel()
    @ObservedObject var settingsService: SettingService = SettingService()
    @State private var isLegalSheetPresented = false
    @State private var isMapSheetPresented = false
    
    var body: some View {
        ZStack {
            ZStack {
                if nowViewModel.updateDidFinish {
                    StarsView()
                        .opacity(nowViewModel.starOpacity)
                    if nowViewModel.isRaining() {
                        CloudsView(
                            thickness: Cloud.Thickness.thick,
                            topTint: nowViewModel.getCloudTopStops().interpolated(amount: nowViewModel.time),
                            bottomTint: nowViewModel.getCloudBottomStops().interpolated(amount: nowViewModel.time)
                        )
                        StormView(type: Storm.Contents.rain, direction: .degrees(30), strength: 80)
                    } else {
                        if (nowViewModel.weather?.currentWeather.getCloudDensity() ?? Cloud.Thickness.none) != Cloud.Thickness.thick {
                            SunView(progress: nowViewModel.time)
                        }
                        CloudsView(
                            thickness: nowViewModel.weather?.currentWeather.getCloudDensity() ?? Cloud.Thickness.none,
                            topTint: nowViewModel.getCloudTopStops().interpolated(amount: nowViewModel.time),
                            bottomTint: nowViewModel.getCloudTopStops().interpolated(amount: nowViewModel.time)
                        )
                    }
                }
            }
            .preferredColorScheme(.dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(colors: [
                    nowViewModel.getBackgroundTopStops().interpolated(amount: nowViewModel.time),
                    nowViewModel.getBackgroundBottomStops().interpolated(amount: nowViewModel.time)
                ], startPoint: .top, endPoint: .bottom)
            )

            

            // MARK: Weather Sheet
            ScrollView(.vertical, showsIndicators: false) {
                ZStack {
                    VStack(alignment: .leading) {
                        HeadView(now: nowViewModel)
                            .padding(.top, 50)
                        RainView(rain: $nowViewModel.rain)
                        HourlyView(weather: $nowViewModel.weather)
                        DailyView(weather: $nowViewModel.weather)
                        
                        Text("Radar")
                            .font(.title3)
                            .bold()
                            .foregroundColor(Color(UIColor.label))
                            .padding([.leading, .top])
                                      
                        AsyncImage(
                            url: URL(string: "https://api.oscars.love/api/v1/mapshots/radar?lat=\(nowViewModel.getCurrentCoords().latitude)&lon=\(nowViewModel.getCurrentCoords().longitude)"),
                            content: { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            },
                            placeholder: {
                                VStack(alignment: .leading) {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                        Spacer()
                                    }
                                    Spacer()
                                }
                                .frame(height: 350)
                                .background(Color(UIColor.secondarySystemFill))
                            }
                        )
                        .cornerRadius(10)
                        .padding()
                        .onTapGesture {
                            UIApplication.shared.playHapticFeedback()
                            isMapSheetPresented.toggle()
                        }
                        .sheet(isPresented: $isMapSheetPresented) {
                            MapDetailView(now: nowViewModel, settingsService: settingsService)
                        }
                    
                        AQIView(aqi: $nowViewModel.aqi)
                                          
                        HStack {
                            Spacer()
                            Image(systemName: "info.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundColor(Color(UIColor.label))
                            Text("Rechtliche\nInformationen")
                                .foregroundColor(Color(UIColor.label))
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
                }
            }
            .padding(.top, 40)
            .refreshable {
                nowViewModel.update()
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
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
