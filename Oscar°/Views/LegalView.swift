//
//  LegalView.swift
//  LegalView
//
//  Created by Philipp Bolte on 28.08.21.
//

import SwiftUI

struct LegalView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Spacer(minLength: 0)) {
                    MemberCard()
                }
                .listRowBackground(Color(UIColor.systemGroupedBackground))
                .listRowInsets(EdgeInsets())
                
                Section(header: Text("Einstellungen")) {
                    NavigationLink {
                        UnitSettings()
                    } label: {
                        UnitSettingsLabel()
                    }
                }
                
                Section(header: Text("Über")) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .frame(width: 30, height: 30)
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .cornerRadius(5)
                        Link(String(localized: "Datenschutz"), destination: URL(string: "https://oscars.love/")!)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .font(.body)
                    }
                    HStack {
                        Image(systemName: "figure.wave")
                            .frame(width: 30, height: 30)
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .cornerRadius(5)
                        Link(String(localized: "Impressum"), destination: URL(string: "https://oscars.love/")!)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .font(.body)
                    }
                }
                
                Section(header: Text("Services")) {
                    NavigationLink {
                        OpenMeteoAttribution()
                    } label: {
                        OpenMeteoLabel()
                    }

                    NavigationLink {
                        BrightSkyAttribution()
                    } label: {
                        BrightSkyLabel()
                    }
                    
                    NavigationLink {
                        TomorrowAttribution()
                    } label: {
                        TomorrowLabel()
                    }
                    
                    NavigationLink {
                        DWDAttribution()
                    } label: {
                        DWDLabel()
                    }
                }
                
                Section(header: Text("Sonstiges")) {
                    HStack {
                        Image(systemName: "swift")
                            .frame(width: 30, height: 30)
                            .foregroundColor(.white)
                            .background(Color.red)
                            .cornerRadius(5)
                        Link("swift-openapi-generator", destination: URL(string: "https://github.com/apple/swift-openapi-generator")!)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .font(.body)
                    }
                    HStack {
                        Image(systemName: "swift")
                            .frame(width: 30, height: 30)
                            .foregroundColor(.white)
                            .background(Color.red)
                            .cornerRadius(5)
                        Link("swift-openapi-runtime", destination: URL(string: "https://github.com/apple/swift-openapi-runtime")!)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .font(.body)
                    }
                    HStack {
                        Image(systemName: "swift")
                            .frame(width: 30, height: 30)
                            .foregroundColor(.white)
                            .background(Color.red)
                            .cornerRadius(5)
                        Link("swift-openapi-urlsession", destination: URL(string: "https://github.com/apple/swift-openapi-urlsession")!)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .font(.body)
                    }
                    HStack {
                        Image(systemName: "sparkles")
                            .frame(width: 30, height: 30)
                            .foregroundColor(.white)
                            .background(Color.red)
                            .cornerRadius(5)
                        Link("Icons by Hosein Bagheri", destination: URL(string: "https://ui8.net/hosein_bagheri/products/3d-weather-icons40")!)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .font(.body)
                    }
                }
                
                NavigationLink {
                    MemoryView()
                        .navigationBarBackButtonHidden()
                } label: {
                    HStack {
                        Spacer()
                        VStack {
                            Text("Oscar° Weather")
                                .font(.body)
                                .bold()
                            Text("by Philipp Bolte")
                                .font(.caption)
                                .padding(.bottom, 2)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 1)
                }
            }
            .navigationBarTitle("Rechtliches", displayMode: .inline)
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarTrailing, content: {
                    Button("Fertig", action: {
                        presentationMode.wrappedValue.dismiss()
                        UIApplication.shared.playHapticFeedback()
                    })
                })
            })
        }
    }
}

struct LegalView_Previews: PreviewProvider {
    static var previews: some View {
        LegalView()
    }
}
