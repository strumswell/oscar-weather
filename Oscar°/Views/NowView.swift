//
//  NowView.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.

import SwiftUI
import OpenAPIRuntime
import OpenAPIURLSession
import MapKit
import WidgetKit

#Preview {
    NowView().preferredColorScheme(.dark)
}

struct NowView: View {
    @ObservedObject var settingsService: SettingService = SettingService()
    @Environment(Weather.self) private var weather: Weather
    @Environment(Location.self) private var location: Location
    @State private var isMapSheetPresented = false
    @State private var tapCount = 0
    @State private var oscarRadarState = OscarRadarState()
    @State private var weatherTileState = WeatherTileState()

    private var client = APIClient()
    private let locationService = LocationService.shared

    var body: some View {
        ZStack {
            WeatherSimulationView()
            ScrollView(.vertical, showsIndicators: false) {
                ZStack {
                    VStack(alignment: .leading) {
                        
                        HeadView()
                            .padding(.top, 50)
                            .onTapGesture {
                                self.tapCount += 1
                                if self.tapCount == 10 {
                                    self.tapCount = 0  // Reset the count if needed
                                    weather.debug.toggle()
                                    UIApplication.shared.playHapticFeedback()
                                }
                            }
                        RainView()
                            .opacity(weather.isLoading ? 0.3 : 1.0)
                            .animation(.easeInOut(duration: 0.3), value: weather.isLoading)
                        HourlyView()
                        DailyView()
                            .opacity(weather.isLoading ? 0.3 : 1.0)
                            .animation(.easeInOut(duration: 0.3), value: weather.isLoading)
                        VStack(alignment: .leading) {
                            Text("Karte")
                                .font(.title3)
                                .bold()
                                .foregroundColor(Color(UIColor.label))
                                .padding([.leading, .top])
                                .onTapGesture {
                                    UIApplication.shared.playHapticFeedback()
                                    isMapSheetPresented.toggle()
                                }
                                .sheet(isPresented: $isMapSheetPresented) {
                                    MapDetailView(settingsService: settingsService)
                                }
                            RadarView(
                                settingsService: settingsService,
                                showLayerSettings: false,
                                userActionAllowed: false,
                                oscarRadarState: oscarRadarState,
                                weatherTileState: weatherTileState
                            )
                                .frame(height: 350)
                                .cornerRadius(10)
                                .padding()
                                .opacity(weather.isLoading ? 0.3 : 1.0)
                                .animation(.easeInOut(duration: 0.3), value: weather.isLoading)
                                .onTapGesture {
                                    UIApplication.shared.playHapticFeedback()
                                    isMapSheetPresented.toggle()
                                }
                                .sheet(isPresented: $isMapSheetPresented) {
                                    MapDetailView(settingsService: settingsService)
                                }
                                .task {
                                    if settingsService.oscarRadarLayer {
                                        await oscarRadarState.loadCurrentFrame()
                                    } else if let layer = settingsService.activeTileLayer {
                                        await weatherTileState.switchLayer(layer)
                                    }
                                }
                                .onChange(of: settingsService.oscarRadarLayer) { _, isEnabled in
                                    if isEnabled {
                                        weatherTileState.pause()
                                        if oscarRadarState.frames.isEmpty {
                                            Task { await oscarRadarState.loadCurrentFrame() }
                                        }
                                    } else {
                                        oscarRadarState.pause()
                                    }
                                }
                                .onChange(of: settingsService.activeTileLayer) { _, newLayer in
                                    if let layer = newLayer {
                                        oscarRadarState.pause()
                                        Task { await weatherTileState.switchLayer(layer) }
                                    } else {
                                        weatherTileState.pause()
                                    }
                                }
                        }

                        AQIView()
                        LegalTextView()
                        if weather.debug {
                            VStack {
                                Text(weather.isLoading.description)
                                Text(weather.error)
                                Text("Air")
                                    .padding(.top, 20)
                                Text(String(reflecting: weather.air))
                                Text("Radar")
                                    .padding(.top, 20)
                                Text(String(reflecting: weather.radar))
                                Text("Alerts")
                                    .padding(.top, 20)
                                Text(String(reflecting: weather.alerts))
                                Text("Time")
                                    .padding(.top, 20)
                                Text(String(reflecting: weather.time))
                                Text("Location")
                                    .padding(.top, 20)
                                Text(String(reflecting: location.coordinates))
                                Text(String(reflecting: location.name))
                                Text("Forecast")
                                    .padding(.top, 20)
                                Text(String(reflecting: weather.forecast))
                            }
                        }
                    }
                }
            }
            .padding(.top, 40)
            .refreshable {
                await self.updateState()
            }
        }
        .background(.thinMaterial)
        .edgesIgnoringSafeArea(.all)
        .task {
            // Periodically refresh radar / tile metadata so the map stays current.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5 * 60))
                guard !Task.isCancelled else { break }
                if settingsService.oscarRadarLayer {
                    await oscarRadarState.loadCurrentFrame()
                } else if settingsService.activeTileLayer != nil {
                    await weatherTileState.loadFrames(forceRefresh: true)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await self.updateState()
                await RainAlertManager.shared.syncLocationUpdate()
                WidgetCenter.shared.reloadAllTimelines()
                if settingsService.oscarRadarLayer {
                    await oscarRadarState.loadCurrentFrame()
                } else if settingsService.activeTileLayer != nil {
                    await weatherTileState.loadFrames(forceRefresh: true)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for:  Notification.Name("ChangedLocation"), object: nil)) { _ in
            Task {
                await self.updateState()
                await RainAlertManager.shared.syncLocationUpdate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for:  Notification.Name("CityToggle"), object: nil)) { _ in
            Task {
                await self.updateState()
                await RainAlertManager.shared.syncLocationUpdate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for:  Notification.Name("UnitChanged"), object: nil)) { _ in
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
            weather.error = error.localizedDescription
            weather.isLoading = false
        }
    }
}
