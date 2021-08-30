//
//  SearchView.swift
//  SearchView
//
//  Created by Philipp Bolte on 16.08.21.
//  Credits to https://www.peteralt.com/blog/mapkit-location-search-with-swiftui/

import SwiftUI
import MapKit

struct SearchView: View {
    @ObservedObject var searchModel: SearchViewModel
    @ObservedObject var now: NowViewModel
    @Binding var cities: [City]
    @Environment(\.presentationMode) var presentationMode
    @State private var showCityList = true
    
    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Ort suchen")) {
                        ZStack(alignment: .trailing) {
                            TextField("Suchen", text: $searchModel.queryFragment, onEditingChanged: {(hasFocus) in
                                if (hasFocus) {
                                    showCityList = false
                                } else {
                                    showCityList = true
                                }
                            })
                        }
                    }
                    
                    if(self.showCityList) {
                        Section(header: Text("Meine Orte")) {
                            List {
                                if (now.lm.authStatus == .authorizedWhenInUse || now.lm.authStatus == .authorizedAlways) {
                                    if (now.cs.cities.filter {$0.selected == true}.count < 1) {
                                        HStack {
                                            Image(systemName: "location.fill")
                                                .foregroundColor(.blue)
                                            Text("Aktueller Standort")
                                            Spacer()
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    } else {
                                        HStack {
                                            Image(systemName: "location.fill")
                                                .foregroundColor(.blue)
                                            Text("Aktueller Standort")
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            now.cs.disableAllCities()
                                        }
                                    }
                                }

                                ForEach(now.cs.cities) { city in
                                    HStack {
                                        if (city.selected) {
                                            Text("\(city.label ?? "")")
                                            Spacer()
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                            
                                        } else {
                                            Text("\(city.label ?? "")")
                                            Spacer()
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        now.cs.toggleActiveCity(city: city)
                                    }
                                }
                                .onDelete(perform: now.cs.deleteCity)
                            }
                        }
                    }
                    
                    
                    Section {
                        List {
                            Group { () -> AnyView in
                                switch searchModel.status {
                                    case .noResults: return AnyView(Text("No Results"))
                                    case .error(let description): return AnyView(Text("Error: \(description)"))
                                    default: return AnyView(EmptyView())
                                }
                            }.foregroundColor(Color.gray)
                            
                            if(searchModel.searchResults.filter{$0.title.contains("Hessen")}.count > 0) {
                                Label("Hessen, Sachsen-Anhalt", systemImage: "plus")
                                    .onTapGesture {
                                        now.cs.addCity(city: ["Hessen", "52.01", "10.77", "false"])
                                        showCityList.toggle()
                                        searchModel.status = .idle
                                        UIApplication.shared.hideKeyboard()
                                    }
                            }
                            
                            ForEach(searchModel.searchResults, id: \.self) { completionResult in
                                Label("\(completionResult.title)", systemImage: "plus")
                                    .onTapGesture {
                                        now.cs.addCity(searchResult: completionResult)
                                        showCityList.toggle()
                                        searchModel.status = .idle
                                        UIApplication.shared.hideKeyboard()
                                    }
                            }
                        }
                    }
                    
                }
            }
            .animation(nil)
            .navigationBarTitle(Text("Orte"), displayMode: .inline)
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

// Thank you to https://stackoverflow.com/questions/56491386/how-to-hide-keyboard-when-using-swiftui
extension UIApplication {
    func hideKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    func playHapticFeedback() {
        let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
        hapticFeedback.impactOccurred()
    }
}

