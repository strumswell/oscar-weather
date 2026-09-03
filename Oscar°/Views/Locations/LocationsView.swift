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

    /// Card backdrops animate only while the list is actually in front; on
    /// another tab or under a sheet the storm layers would render unseen.
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
                        // No map.badge.plus exists in SF Symbols, so the
                        // badge.plus treatment is composed from system
                        // glyphs. (The MapBadgePlus.symbolset compiles into
                        // the catalog but the iOS 26 runtime refuses to load
                        // it — SwiftUI faults "No image named … found in
                        // asset catalog".)
                        // A ZStack, not a Label: the toolbar extracts a
                        // Label's icon down to the bare symbol and strips
                        // composed overlays.
                        Button(action: presentMapPicker) {
                            Image(systemName: "map")
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .symbolRenderingMode(.palette)
                                        // Plus knocked out in the (dynamic)
                                        // background color, disc in the label
                                        // color; the scaled backing circle
                                        // fakes the SF badge knockout against
                                        // the map. Explicit color — the
                                        // .background STYLE renders as a hazy
                                        // material on the glass toolbar.
                                        .foregroundStyle(Color(.systemBackground), .primary)
                                        .background {
                                            Circle()
                                                .fill(Color(.systemBackground))
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
                            Haptics.impact()
                            isSearchPresented = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(Text("Ort hinzufügen"))
                        .accessibilityHint(Text("Öffnet die Suche"))
                    }
                }
        }
        // On the NavigationStack, not the list content. Attached inside the
        // stack, the system's round dismiss button survived a swipe-down
        // dismissal and kept covering the nav bar header.
        .searchable(text: $searchText, isPresented: $isSearchPresented)
        .onChange(of: isSearchPresented) { _, presented in
            // A swipe-down dismissal keeps the typed text otherwise, leaving
            // the list in results mode with no visible search field.
            if !presented { searchText = "" }
        }
        // A re-tap on the active Orte tab jumps straight into the search.
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
                // Cancellation arrives in wrapped shapes too (middleware
                // ClientError around CancellationError / URLError -999), so the
                // task flag is the reliable signal. A cancelled task must not
                // touch state — the newer search owns it already.
                guard !Task.isCancelled else { return }
                searchResult = .init()
                searchError = error.localizedDescription
            }
            isSearchInFlight = false
        }
    }

    // MARK: - List

    /// ONE List for both the saved places and the search results. Swapping
    /// whole views here (list ↔ results ↔ "no results") tears down siblings of
    /// the search field mid-typing and cost it first-responder status; content
    /// swaps inside a stable List identity don't.
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
        ForEach(searchResult.results ?? [], id: \.self) { result in
            LocationSearchResultRow(result: result) {
                preview(result)
            }
        }
    }

    /// Error/loading/empty state over the (then row-less) list. "No results"
    /// only after a search actually completed — while one is in flight the
    /// overlay is a spinner, and earlier results stay in the rows below it.
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

    /// Picking a place answers "what's the weather there" — jump to the forecast.
    private func showForecast() {
        presentation.selectedTab = .forecast
    }

    private func presentMapPicker() {
        Haptics.impact()
        isMapPresented = true
    }

    private func delete(_ city: City) {
        guard let index = cities.firstIndex(of: city) else { return }
        locationService.city.deleteCity(offsets: IndexSet(integer: index))
    }

    private func preview(_ result: Components.Schemas.Location) {
        guard let lat = result.latitude, let lon = result.longitude else { return }
        Haptics.impact()
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
