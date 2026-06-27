import SwiftUI

struct SearchCityView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchIsActive = false
    @State private var searchResult: Components.Schemas.SearchResponse = .init()
    @State private var refreshID = UUID()
    private let client = APIClient.shared
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
                                Button {
                                    locationService.city.addCity(searchResult: result)
                                    searchIsActive = false
                                    searchText = ""
                                    UIApplication.shared.hideKeyboard()
                                } label: {
                                    Text(getFormattedLocationString(location: result))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Orte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarTrailing, content: {
                    Button(role: .close) {
                        dismiss()
                        UIApplication.shared.playHapticFeedback()
                    }
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
                                            .foregroundStyle(.blue)
                                        Text("Aktueller Standort")
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                } else {
                                    Button {
                                        locationService.city.disableAllCities()
                                    } label: {
                                        HStack {
                                            Image(systemName: "location.fill")
                                                .foregroundStyle(.blue)
                                            Text("Aktueller Standort")
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            ForEach(locationService.city.cities) { city in
                                Button {
                                    locationService.city.toggleActiveCity(city: city)
                                } label: {
                                    HStack {
                                        if (city.selected) {
                                            Text("\(city.label ?? "")")
                                            Spacer()
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)

                                        } else {
                                            Text("\(city.label ?? "")")
                                            Spacer()
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityValue(city.selected ? Text("Ausgewählt") : Text(""))
                                .id("\(city.objectID.uriRepresentation())-\(city.selected)")
                            }
                            .onDelete(perform: locationService.city.deleteCity)
                            .onMove(perform: locationService.city.moveCity)
                        }
                        .id(refreshID)
                    }
                }
            }
        }
        .searchable(text: $searchText, isPresented: $searchIsActive, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Suchen..."))
        .onReceive(NotificationCenter.default.publisher(for: .cityToggle)) { _ in
            refreshID = UUID()
        }
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
#Preview {
    SearchCityView()
}
