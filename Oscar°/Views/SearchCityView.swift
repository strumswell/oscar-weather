import SwiftUI

struct SearchCityView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var searchText = ""
    @State private var searchIsActive = false
    @State private var searchResult: Components.Schemas.SearchResponse = .init()
    private var client = APIClient()
    private var locationService = LocationService.shared

    var body: some View {
        
        NavigationStack {
            VStack {
                if searchIsActive {
                    if (searchText.count > 0 && (searchResult.results?.isEmpty) == nil) {
                        ContentUnavailableView.search
                    } else {
                        List {
                            ForEach(searchResult.results ?? [], id: \.self) { result in
                                HStack {
                                    Text(getFormattedLocationString(location: result))
                                        .onTapGesture {
                                            locationService.city.addCity(searchResult: result)
                                            searchIsActive = false
                                            searchText = ""
                                            UIApplication.shared.hideKeyboard()
                                        }
                                }
                                .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationBarTitle(String(localized: "Orte"), displayMode: .inline)
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarTrailing, content: {
                    Button(String(localized: "Fertig"), action: {
                        presentationMode.wrappedValue.dismiss()
                        UIApplication.shared.playHapticFeedback()
                    })
                })
            })
            
            if !searchIsActive {
                Form {
                    Section(header: Text("Meine Orte")) {
                        List {
                            if (locationService.authStatus == .authorizedWhenInUse || locationService.authStatus == .authorizedAlways) {
                                if (locationService.city.cities.filter {$0.selected == true}.count < 1) {
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
                                        locationService.city.disableAllCities()
                                    }
                                }
                            }
                            
                            ForEach(locationService.city.cities) { city in
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
                                    locationService.city.toggleActiveCity(city: city)
                                }
                            }
                            .onDelete(perform: locationService.city.deleteCity)
                            .onMove(perform: locationService.city.moveCity)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, isPresented: $searchIsActive, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Suchen..."))
        .onChange(of: searchText, {
            Task {
                if searchText.count < 1 { return }
                searchResult = try await client.getGeocodeSearchResult(name: searchText)
            }
        })
    }
}

extension SearchCityView {
    public func getFormattedLocationString(location: Components.Schemas.Location) -> String {
        let locationDetails = [location.name, location.admin3, location.admin1, location.country]
        let formattedString = locationDetails.compactMap { $0 }.joined(separator: ", ")
        
        return formattedString.isEmpty ? "Unknown Entry" : formattedString
    }
}

// Preview
struct SearchCityView_Previews: PreviewProvider {
    static var previews: some View {
        SearchCityView()
    }
}
