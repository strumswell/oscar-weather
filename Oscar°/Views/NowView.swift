//
//  NowView.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.

import SwiftUI
import SPIndicator
import OpenAPIRuntime
import OpenAPIURLSession

#Preview {
    NowView().preferredColorScheme(.dark)
}

struct NowView: View {
    @ObservedObject var nowViewModel: NowViewModel = NowViewModel()
    @ObservedObject var settingsService: SettingService = SettingService()
    @State private var isLegalSheetPresented = false
    @State private var isMapSheetPresented = false
        
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location

    private var client = APIClient()
    private let locationService = LocationService()


    var body: some View {
        ZStack {
            ZStack {
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
                        bottomTint: nowViewModel.getCloudBottomStops().interpolated(amount: nowViewModel.time)
                    )
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
                        .overlay(
                            ZStack {
                                Circle()
                                    .foregroundColor(.white)
                                    .shadow(radius: 5)
                                    .frame(width: 18, height: 18)
                                Circle()
                                    .foregroundColor(.blue)
                                    .frame(width: 13, height: 13)
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
                await self.updateState()
            }
            .task {
                //await nowViewModel.update()
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .edgesIgnoringSafeArea(.all)
        .onReceive(NotificationCenter.default.publisher(for:  Notification.Name("ChangedLocation"), object: nil)) { _ in
            Task {
                await self.updateState()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for:  Notification.Name("CityToggle"), object: nil)) { _ in
            Task {
                await self.updateState()
            }
        }
    }
}

extension NowView {
    func updateState() async {
        do {
            locationService.update()
            location.coordinates = locationService.getCoordinates()
            location.name = await locationService.getLocationName()
            weather.forecast = try await client.getForecast(coordinates: location.coordinates)
        } catch {
            print(error)
        }
    }

}
