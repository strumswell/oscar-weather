//
//  RadarImageView.swift
//  Oscar°
//
//  Created by Philipp Bolte on 04.01.24.
//

import SwiftUI

struct RadarImageView: View {
    @Environment(Location.self) private var location: Location
    @ObservedObject var nowViewModel: NowViewModel
    @ObservedObject var settingsService: SettingService

    @State private var isMapSheetPresented = false

    var body: some View {
        VStack(alignment: .leading) {
            Text("Radar")
                .font(.title3)
                .bold()
                .foregroundColor(Color(UIColor.label))
                .padding([.leading, .top])
            
            AsyncImage(
                url: URL(string: "https://api.oscars.love/api/v1/mapshots/radar?lat=\(location.coordinates.latitude)&lon=\(location.coordinates.longitude)"),
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
        }
        .scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.8)
                .scaleEffect(phase.isIdentity ? 1 : 0.99)
                .blur(radius: phase.isIdentity ? 0 : 0.5)
        }
    }
}
