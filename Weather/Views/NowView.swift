//
//  NowView.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.

import SwiftUI

struct NowView: View {
    @ObservedObject var nowViewModel: NowViewModel = NowViewModel()
    @State private var isLegalSheetPresented = false

    var body: some View {
        VStack {
            ScrollView(.vertical, showsIndicators: false) {
                RefreshView(coordinateSpace: .named("RefreshView"), nowViewModel: nowViewModel)
                HeadView(now: nowViewModel)
                
                VStack(alignment: .leading) {
                    Spacer().frame(height: 20)
                    RainView(weather: $nowViewModel.weather)
                    HourlyView(weather: $nowViewModel.weather)
                    DailyView(weather: $nowViewModel.weather)
                    RadarView(now: nowViewModel, radarMetadata: $nowViewModel.currentRadarMetadata)
                    HStack {
                        Spacer()
                        Image(systemName: "info.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.white.opacity(0.5))
                        Text("Rechtliche\nInformationen")
                            .foregroundColor(.white.opacity(0.5))
                            .font(.system(size: 10))
                            .bold()
                        Spacer()
                    }
                    .padding(.bottom, 50)
                    .onTapGesture {
                        UIApplication.shared.playHapticFeedback()
                        isLegalSheetPresented.toggle()
                    }
                    .sheet(isPresented: $isLegalSheetPresented) {
                        LegalView()
                    }
                }
                .background(LinearGradient(gradient: Gradient(colors: [.clear, Color("gradientBlueLight-5").opacity(0.7)]), startPoint: .bottom, endPoint: .center))
                .cornerRadius(25)
            }
            .coordinateSpace(name: "RefreshView")
        }
        .padding(.top)
        .background(LinearGradient(gradient: Gradient(colors: [.black, Color("gradientBlueDark-7")]), startPoint: .top, endPoint: .center))
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            nowViewModel.update()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            nowViewModel.update()
        }
        .onReceive(NotificationCenter.default.publisher(for:  Notification.Name("ChangedLocation"), object: nil)) { _ in
            nowViewModel.update()
        }
        .onReceive(NotificationCenter.default.publisher(for:  Notification.Name("CityToggle"), object: nil)) { _ in
            nowViewModel.update()
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
