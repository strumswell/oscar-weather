//
//  NowView.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.

import SwiftUI
import SPIndicator
import OpenAPIRuntime
import OpenAPIURLSession
import MapKit

#Preview {
    NowView().preferredColorScheme(.dark)
}

struct NowView: View {
    @ObservedObject var nowViewModel: NowViewModel = NowViewModel()
    @ObservedObject var settingsService: SettingService = SettingService()    
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location
    @State private var isMapSheetPresented = false

    private var client = APIClient()
    private let locationService = LocationService.shared

    var body: some View {
        ZStack {
            WeatherSimulationView()
            ScrollView(.vertical, showsIndicators: false) {
                ZStack {
                    VStack(alignment: .leading) {
                        HeadView(now: nowViewModel)
                            .padding(.top, 50)
                        RainView()
                        HourlyView()
                        DailyView()
                        VStack(alignment: .leading) {
                            Text("Radar")
                                .font(.title3)
                                .bold()
                                .foregroundColor(Color(UIColor.label))
                                .padding([.leading, .top])
                            RadarView(settingsService: settingsService, radarMetadata: $nowViewModel.currentRadarMetadata, showLayerSettings: false, userActionAllowed: false)
                                .frame(height: 350)
                                .cornerRadius(10)
                                .padding()
                                .onTapGesture {
                                    UIApplication.shared.playHapticFeedback()
                                    isMapSheetPresented.toggle()
                                }
                                .sheet(isPresented: $isMapSheetPresented) {
                                    MapDetailView(now: nowViewModel, settingsService: settingsService)
                                }
                        }

                        //RadarImageView(nowViewModel: nowViewModel, settingsService: settingsService)
                        AQIView()
                        LegalTextView()
                    }
                }
            }
            .padding(.top, 40)
            .refreshable {
                await self.updateState()
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .edgesIgnoringSafeArea(.all)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await self.updateState()
            }
        }
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
            if weather.isLoading { return }
            weather.isLoading = true
            
            locationService.update()
            location.coordinates = locationService.getCoordinates()
            location.name = await locationService.getLocationName()
            
            async let forecastRequest = client.getForecast(coordinates: location.coordinates)
            async let airQualityRequest = client.getAirQuality(coordinates: location.coordinates)
            async let radarRequest = client.getRainRadar(coordinates: location.coordinates)
            let (forecastResponse, airQualityResponse, radarResponse) = try await (forecastRequest, airQualityRequest, radarRequest)
            weather.forecast = forecastResponse
            weather.air = airQualityResponse
            weather.radar = radarResponse
            weather.updateTime()
            weather.isLoading = false
            
            let alertsResponse = try await client.getAlerts(coordinates: location.coordinates)
            weather.alerts = alertsResponse
        } catch {
            print(error)
        }
    }
}
