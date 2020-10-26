//
//  ContentView.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.
//  Weather icons by Rasmus Nielsen https://www.iconfinder.com/iconsets/weatherful

import SwiftUI
import MapKit


struct ContentView: View {
    @State var weather = WeatherResponse()
    
    let locationManager = CLLocationManager()
    let defaultCoordinate = CLLocationCoordinate2D.init(latitude: 52.41667, longitude: 12.55)

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color("gradientBlueLight"), Color("gradientBlueDark")]), startPoint: .top, endPoint: .bottom)
            VStack {
                ScrollView(.vertical, showsIndicators: false) {
                    HeadView(weather: self.$weather)
                    VStack(alignment: .leading) {
                        RainView(weather: self.$weather)
                        HourlyView(weather: self.$weather)
                        DailyView(weather: self.$weather)
                        HStack {
                            Spacer()
                            Text("Oscar° by Philipp Bolte")
                                .font(.caption)
                                .fontWeight(.light)
                            Spacer()
                        }
                        .padding(.bottom, 25)
                    }
                }
                .padding(.top)
            }
        }
        .foregroundColor(.white)
        .edgesIgnoringSafeArea(.all)
        .onAppear(perform: getWeatherData)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            getWeatherData()
        }
    }
    
    // Thanks to https://www.hackingwithswift.com/books/ios-swiftui/sending-and-receiving-codable-data-with-urlsession-and-swiftui
    func getWeatherData() {
        let coordinate = self.defaultCoordinate //locationManager.location?.coordinate ?? self.defaultCoordinate
        
        guard let url = URL(string: "https://radar.bolte.cloud/api/v2/weather/forecast?lat=\(coordinate.latitude)&lon=\(coordinate.longitude)&key=") else {
            print("Invalid URL")
            return
        }
        let request = URLRequest(url: url)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let data = data {
                if let decodedResponse = try? JSONDecoder().decode(WeatherResponse.self, from: data) {
                    DispatchQueue.main.async {
                        self.weather = decodedResponse.self
                    }
                    return
                }
            }
            print("Fetch failed: \(error?.localizedDescription ?? "Unknown error")")
        }.resume()
    }
}



struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.light)
    }
}
