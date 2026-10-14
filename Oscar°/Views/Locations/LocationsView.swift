//
//  LocationsView.swift
//  Oscar°
//
//  Location management 2.0: saved places as live-conditions cards, text
//  search, a map point picker, and a forecast preview before adding.
//

import CoreLocation
import SwiftUI

struct LocationsView: View {
    @Environment(NowPresentationCoordinator.self) private var presentation
    @State private var searchText = ""
    @State private var searchResult: Components.Schemas.SearchResponse = .init()
    @State private var searchError: String?
    @State private var isSearchInFlight = false
    @State private var isMapPresented = false
    @State private var isSearchPresented = false
    @State private var candidate: LocationCandidate?
    @State private var editTarget: LocationEditTarget?
    @State private var selectedCityURI: URL?
    @State private var selectionCount = 0
    private let client = APIClient.shared
    private var locationService = LocationService.shared
    private var conditionsStore = CityConditionsStore.shared

    private var gpsAuthorized: Bool {
        locationService.authStatus == .authorizedWhenInUse
            || locationService.authStatus == .authorizedAlways
    }

    private var cities: [City] {
        locationService.city.cities
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    private var cardBackdropsPaused: Bool {
        presentation.selectedTab != .places
            || presentation.sheet != nil
            || candidate != nil
            || editTarget != nil
            || isMapPresented
    }

    var body: some View {
        NavigationStack {
            locationList
                .navigationTitle("Orte")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: presentMapPicker) {
                            Image(systemName: "map")
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(Color(uiColor: .systemBackground), .primary)
                                        .background {
                                            Circle()
                                                .fill(Color(uiColor: .systemBackground))
                                                .scaleEffect(1.3)
                                        }
                                        .offset(x: 4, y: 4)
                                }
                        }
                        .accessibilityLabel(Text("Karte"))
                        .accessibilityHint(Text("Öffnet die Karte"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isSearchPresented = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(Text("Ort hinzufügen"))
                        .accessibilityHint(Text("Öffnet die Suche"))
                    }
                }
        }
        .searchable(text: $searchText, isPresented: $isSearchPresented)
        .onChange(of: isSearchPresented) { _, presented in
            if !presented { searchText = "" }
        }
        .onChange(of: presentation.placesSearchRequests) {
            isSearchPresented = true
        }
        .sheet(item: $candidate) { candidate in
            LocationPreviewSheet(candidate: candidate) {
                add(candidate)
            }
        }
        .sheet(item: $editTarget) { target in
            LocationEditSheet(target: target)
        }
        .fullScreenCover(isPresented: $isMapPresented) {
            LocationMapSheet(
                cities: cities,
                initialCenter: locationService.getCoordinates()
            ) { picked in
                add(picked)
            }
        }
        .sensoryFeedback(.selection, trigger: selectionCount)
        .onReceive(NotificationCenter.default.publisher(for: .cityToggle)) { _ in
            selectedCityURI = locationService.city.getSelectedCity()?.objectID.uriRepresentation()
        }
        .task {
            selectedCityURI = locationService.city.getSelectedCity()?.objectID.uriRepresentation()
        }
        .task(id: conditionsKey) {
            await conditionsStore.refresh(coordinates: conditionCoordinates)
        }
        .task(id: searchText) {
            searchError = nil
            guard !searchText.isEmpty else {
                searchResult = .init()
                isSearchInFlight = false
                return
            }
            isSearchInFlight = true
            do {
                try await Task.sleep(for: .milliseconds(300))
                searchResult = try await client.getGeocodeSearchResult(name: searchText)
            } catch {
                guard !Task.isCancelled else { return }
                searchResult = .init()
                searchError = error.localizedDescription
            }
            isSearchInFlight = false
        }
    }

    // MARK: - List

    private var locationList: some View {
        List {
            if isSearching {
                searchResultRows
            } else {
                if gpsAuthorized {
                    Section {
                        currentLocationRow
                    }
                }

                Section {
                    ForEach(cities, id: \.objectID) { city in
                        cityRow(city)
                    }
                    .onMove(perform: locationService.city.moveCity)
                    .onDelete(perform: locationService.city.deleteCity)
                }

                if cities.isEmpty {
                    Section {
                        LocationsEmptyHint()
                            .listRowStyling()
                    }
                }
            }
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .contentMargins(.bottom, 24, for: .scrollContent)
        .overlay {
            searchStatusOverlay
        }
    }

    private var currentLocationRow: some View {
        CurrentLocationRow(
            conditions: currentLocationConditions,
            isSelected: selectedCityURI == nil,
            isDefault: locationService.city.defaultIsCurrentLocation,
            backdropPaused: cardBackdropsPaused,
            onSelect: selectCurrentLocation,
            onEdit: { editTarget = .currentLocation },
            onToggleDefault: {
                locationService.city.setDefault(
                    city: nil,
                    asCurrentLocation: !locationService.city.defaultIsCurrentLocation
                )
            }
        )
    }

    private func cityRow(_ city: City) -> some View {
        LocationCityRow(
            personalization: city.personalization,
            isDefault: city.isDefault,
            conditions: conditionsStore.conditions(
                for: CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
            ),
            isSelected: city.objectID.uriRepresentation() == selectedCityURI,
            backdropPaused: cardBackdropsPaused,
            onSelect: { select(city) },
            onEdit: { editTarget = .city(city) },
            onDelete: { delete(city) },
            onToggleDefault: { locationService.city.setDefault(city: city.isDefault ? nil : city) }
        )
    }

    // MARK: - Search

    private var searchResultRows: some View {
        ForEach(searchResult.results ?? [], id: \.id) { result in
            LocationSearchResultRow(result: result) {
                preview(result)
            }
        }
    }

    @ViewBuilder
    private var searchStatusOverlay: some View {
        if isSearching {
            if let searchError {
                ContentUnavailableView(
                    "Suche fehlgeschlagen",
                    systemImage: "wifi.exclamationmark",
                    description: Text(searchError)
                )
            } else if searchResult.results?.isEmpty ?? true {
                if isSearchInFlight {
                    ProgressView()
                } else {
                    ContentUnavailableView.search
                }
            }
        }
    }

    // MARK: - Actions

    private var conditionCoordinates: [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        if gpsAuthorized {
            coordinates.append(locationService.gpsLocation)
        }
        coordinates.append(contentsOf: cities.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        })
        return coordinates
    }

    private var conditionsKey: String {
        conditionCoordinates
            .map(LocationService.outboundCoordinate)
            .map { "\($0.latitude),\($0.longitude)" }
            .joined(separator: ";")
    }

    private var currentLocationConditions: CityConditions? {
        guard gpsAuthorized else { return nil }
        return conditionsStore.conditions(for: locationService.gpsLocation)
    }

    private func select(_ city: City) {
        selectionCount += 1
        locationService.city.toggleActiveCity(city: city)
        showForecast()
    }

    private func selectCurrentLocation() {
        selectionCount += 1
        if locationService.city.getSelectedCity() != nil {
            locationService.city.disableAllCities()
        }
        showForecast()
    }

    private func showForecast() {
        presentation.selectedTab = .forecast
    }

    private func presentMapPicker() {
        isMapPresented = true
    }

    private func delete(_ city: City) {
        guard let index = cities.firstIndex(of: city) else { return }
        locationService.city.deleteCity(offsets: IndexSet(integer: index))
    }

    private func preview(_ result: Components.Schemas.Location) {
        guard let lat = result.latitude, let lon = result.longitude else { return }
        candidate = LocationCandidate(
            name: result.displayName,
            detail: result.detailLine,
            latitude: Double(lat),
            longitude: Double(lon)
        )
    }

    private func add(_ candidate: LocationCandidate) {
        locationService.city.addCity(
            name: candidate.name,
            latitude: candidate.latitude,
            longitude: candidate.longitude
        )
        Haptics.impact()
        self.candidate = nil
        isMapPresented = false
        searchText = ""
        showForecast()
    }
}

#Preview {
    LocationsView()
        .environment(Weather.mock)
        .environment(NowPresentationCoordinator())
}
