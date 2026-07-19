//
//  LocationsView.swift
//  Oscar°
//
//  Location management 2.0: saved places as live-conditions cards, text
//  search, a map point picker, and a forecast preview before adding.
//

import CoreLocation
import SwiftUI

/// A place the user is about to add: from a search result or a map tap.
/// The preview sheet shows its forecast before anything is saved.
struct LocationCandidate: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var detail: String?
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

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
        presentation.selectedTab != .search
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
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Karte", systemImage: "map", action: presentMapPicker)
                            .accessibilityHint(Text("Öffnet die Karte"))
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Einstellungen", systemImage: "gearshape") {
                            presentation.present(.settings)
                        }
                        .accessibilityHint(Text("Öffnet die Einstellungen"))
                    }
                }
        }
        // On the NavigationStack, not the list content — the canonical shape
        // for the search tab's pill morph. Attached inside the stack, the
        // system's round dismiss button survived a swipe-down dismissal and
        // kept covering the nav bar header.
        .searchable(text: $searchText, isPresented: $isSearchPresented)
        .onChange(of: isSearchPresented) { _, presented in
            // A swipe-down dismissal keeps the typed text otherwise, leaving
            // the list in results mode with no visible search field.
            if !presented { searchText = "" }
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
                        emptyHint
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
        Button {
            selectCurrentLocation()
        } label: {
            CurrentLocationCard(
                conditions: currentLocationConditions,
                isSelected: selectedCityURI == nil,
                backdropPaused: cardBackdropsPaused
            )
        }
        .buttonStyle(LocationCardButtonStyle())
        .contextMenu {
            Button {
                editTarget = .currentLocation
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            currentLocationDefaultButton
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                editTarget = .currentLocation
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            .tint(.indigo)
        }
        .swipeActions(edge: .leading) {
            currentLocationDefaultButton
                .tint(.yellow)
        }
        .listRowStyling()
        .moveDisabled(true)
        .deleteDisabled(true)
    }

    private func cityRow(_ city: City) -> some View {
        Button {
            select(city)
        } label: {
            CityCard(
                city: city,
                conditions: conditionsStore.conditions(
                    for: CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
                ),
                isSelected: city.objectID.uriRepresentation() == selectedCityURI,
                backdropPaused: cardBackdropsPaused
            )
        }
        .buttonStyle(LocationCardButtonStyle())
        .contextMenu {
            Button {
                editTarget = .city(city)
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            defaultButton(for: city)
            Button(role: .destructive) {
                delete(city)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(city)
            } label: {
                Label("Löschen", systemImage: "trash")
            }
            // Explicit red: the role's default is lost to the tab bar's
            // cascading white tint, same reason the neighbors set theirs.
            .tint(.red)
            Button {
                editTarget = .city(city)
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            .tint(.indigo)
        }
        .swipeActions(edge: .leading) {
            defaultButton(for: city)
                .tint(.yellow)
        }
        .listRowStyling()
    }

    @ViewBuilder
    private func defaultButton(for city: City) -> some View {
        if city.isDefault {
            Button {
                locationService.city.setDefault(city: nil)
            } label: {
                Label("Standard entfernen", systemImage: "star.slash")
            }
        } else {
            Button {
                locationService.city.setDefault(city: city)
            } label: {
                Label("Als Standard festlegen", systemImage: "star")
            }
        }
    }

    @ViewBuilder
    private var currentLocationDefaultButton: some View {
        if locationService.city.defaultIsCurrentLocation {
            Button {
                locationService.city.setDefault(city: nil)
            } label: {
                Label("Standard entfernen", systemImage: "star.slash")
            }
        } else {
            Button {
                locationService.city.setDefault(city: nil, asCurrentLocation: true)
            } label: {
                Label("Als Standard festlegen", systemImage: "star")
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Noch keine Orte gespeichert.")
                .font(.headline)
            Text("Suche nach einem Ort oder wähle einen Punkt auf der Karte.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Search

    private var searchResultRows: some View {
        ForEach(searchResult.results ?? [], id: \.self) { result in
            Button {
                preview(result)
            } label: {
                HStack(spacing: 10) {
                    Text(flagEmoji(countryCode: result.country_code) ?? "📍")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name ?? String(localized: "Unbekannter Ort"))
                            .foregroundStyle(.primary)
                        if let detail = formattedDetail(for: result) {
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
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
        UIApplication.shared.playHapticFeedback()
        isMapPresented = true
    }

    private func delete(_ city: City) {
        guard let index = cities.firstIndex(of: city) else { return }
        locationService.city.deleteCity(offsets: IndexSet(integer: index))
    }

    private func preview(_ result: Components.Schemas.Location) {
        guard let lat = result.latitude, let lon = result.longitude else { return }
        UIApplication.shared.playHapticFeedback()
        candidate = LocationCandidate(
            name: result.name ?? String(localized: "Unbekannter Ort"),
            detail: formattedDetail(for: result),
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
        UIApplication.shared.playHapticFeedback()
        self.candidate = nil
        isMapPresented = false
        searchText = ""
        showForecast()
    }

    private func formattedDetail(for location: Components.Schemas.Location) -> String? {
        let detail = [location.admin3, location.admin1, location.country]
            .compactMap { $0 }
            .filter { $0 != location.name }
            .joined(separator: ", ")
        return detail.isEmpty ? nil : detail
    }

    private func flagEmoji(countryCode: String?) -> String? {
        guard let countryCode = countryCode?.uppercased(), countryCode.count == 2 else {
            return nil
        }
        var flag = ""
        for scalar in countryCode.unicodeScalars {
            guard let regional = UnicodeScalar(0x1F1E6 + scalar.value - UnicodeScalar("A").value) else {
                return nil
            }
            flag.unicodeScalars.append(regional)
        }
        return flag
    }
}

// MARK: - Row cards

/// City row content as its own view, observing the managed object directly:
/// List rows diff by ForEach element, and an edited City is the SAME reference
/// as before — without the subscription a label/emoji edit never re-renders
/// the row until the sheet is reopened.
private struct CityCard: View {
    @ObservedObject var city: City
    let conditions: CityConditions?
    let isSelected: Bool
    let backdropPaused: Bool

    var body: some View {
        let detail = [conditions?.conditionText, city.displayDetail]
            .compactMap { $0 }
            .joined(separator: " · ")

        LocationCard(
            title: city.displayName,
            detail: detail.isEmpty ? nil : detail,
            emoji: city.emoji,
            temperature: conditions?.temperature,
            snapshot: conditions?.snapshot,
            isSelected: isSelected,
            isDefault: city.isDefault,
            backdropPaused: backdropPaused
        )
    }
}

/// The GPS pseudo-entry's card: personalization and the default flag come from
/// CityService's observable UserDefaults mirror instead of a City entity —
/// read HERE in body (not passed in) so the lazy List row re-renders on its
/// own observation, independent of parent/row diffing.
private struct CurrentLocationCard: View {
    let conditions: CityConditions?
    let isSelected: Bool
    let backdropPaused: Bool
    private var cityService = CityService.shared

    init(conditions: CityConditions?, isSelected: Bool, backdropPaused: Bool) {
        self.conditions = conditions
        self.isSelected = isSelected
        self.backdropPaused = backdropPaused
    }

    var body: some View {
        let hasCustomLabel = cityService.currentLocationCustomLabel?.isEmpty == false
        let detail = [
            conditions?.conditionText,
            hasCustomLabel ? String(localized: "Aktueller Standort") : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")

        LocationCard(
            title: cityService.currentLocationDisplayName,
            detail: detail.isEmpty ? nil : detail,
            emoji: cityService.currentLocationEmoji,
            temperature: conditions?.temperature,
            snapshot: conditions?.snapshot,
            isSelected: isSelected,
            isDefault: cityService.defaultIsCurrentLocation,
            isCurrentLocation: true,
            backdropPaused: backdropPaused
        )
    }
}

private extension View {
    /// Card rows manage their own background and spacing.
    func listRowStyling() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

#Preview {
    LocationsView()
        .environment(Weather.mock)
        .environment(NowPresentationCoordinator())
}
