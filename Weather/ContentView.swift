//
//  ContentView.swift
//  Weather
//
//  Created by Philipp Bolte on 22.09.20.
//

import SwiftUI
import MapKit


struct ContentView: View {
    @ObservedObject var locationViewModel = LocationViewModel()
    
    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color("gradientBlueLight"), Color("gradientBlueDark")]), startPoint: .top, endPoint: .bottom)
            VStack {
                VStack(alignment: .center) {
                    Text("Brandenburg an der Havel")
                        .font(.title)
                        .fontWeight(.regular)
                        .padding(.bottom)
                    Text("10°")
                        .font(.system(size: 90))
                        .fontWeight(.regular)
                        .padding(.bottom)
                    Text("Leichter Regen")
                        .font(.title3)
                        .padding(.bottom)
                }
                .padding(.top, 120)
                
                ScrollView(.vertical) {
                    VStack(alignment: .leading) {
                        Text("Stunden")
                            .font(.system(size: 20))
                            .bold()
                            .padding()
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 30) {
                                VStack {
                                    Text("16 Uhr")
                                        .padding(.bottom)
                                    Text("☁️")
                                        .padding(.bottom)
                                    Text("14°")
                                }
                                VStack {
                                    Text("17 Uhr")
                                        .padding(.bottom)
                                    Text("☁️")
                                        .padding(.bottom)
                                    Text("13°")
                                }
                                VStack {
                                    Text("18 Uhr")
                                        .padding(.bottom)
                                    Text("🌧️")
                                        .padding(.bottom)
                                    Text("10°")
                                }
                                VStack {
                                    Text("19 Uhr")
                                        .padding(.bottom)
                                    Text("🌧️")
                                        .padding(.bottom)
                                    Text("8°")
                                }
                                VStack {
                                    Text("20 Uhr")
                                        .padding(.bottom)
                                    Text("🌧️")
                                        .padding(.bottom)
                                    Text("8°")
                                }
                                VStack {
                                    Text("21 Uhr")
                                        .padding(.bottom)
                                    Text("🌧️")
                                        .padding(.bottom)
                                    Text("7°")
                                }
                                VStack {
                                    Text("22 Uhr")
                                        .padding(.bottom)
                                    Text("🌧️")
                                        .padding(.bottom)
                                    Text("8°")
                                }
                            }
                            .font(.system(size: 18))
                            .padding(.leading)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top)
            }
        }
        .foregroundColor(.white)
        .edgesIgnoringSafeArea(.all)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.light)
    }
}
