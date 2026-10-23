//
//  OnboardingManualLocationStep.swift
//  Oscar°
//

import SwiftUI

struct OnboardingManualLocationStep: View {
    let onContinue: () -> Void

    private let locationService = LocationService.shared
    private let client = APIClient.shared

    @State private var searchText = ""
    @State private var results: [Components.Schemas.Location] = []
    @State private var searchError: String?
    @State private var appeared = false
    @FocusState private var searchFocused: Bool

    private var selectedCity: City? {
        locationService.city.getSelectedCity()
    }

    var body: some View {
        OnboardingPage {
            EmptyView()
        } content: {
            page
        } buttons: {
            if !searchFocused {
                OnboardingButtonStack(
                    primaryTitle: "Weiter",
                    primaryDisabled: selectedCity == nil,
                    primaryAction: onContinue
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.smooth(duration: 0.3), value: searchFocused)
        .animation(.smooth(duration: 0.35), value: results.count)
        .animation(.smooth(duration: 0.4), value: selectedCity?.objectID)
        .sensoryFeedback(.selection, trigger: selectedCity?.objectID)
        .onAppear { appeared = true }
        .task {
            guard selectedCity == nil else { return }
            try? await Task.sleep(for: .milliseconds(450))
            searchFocused = true
        }
        .task(id: searchText) {
            await search()
        }
    }

    private var page: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.onboardingTitle)
                    .contentTransition(.opacity)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .onboardingEntrance(appeared, delay: 0.05)

            searchField
                .onboardingEntrance(appeared, delay: 0.15)

            resultsList
        }
        .padding(.top, 40)
    }

    private var title: String {
        if let name = selectedCity?.label, !name.isEmpty {
            return name
        }
        return String(localized: "Welcher Ort?")
    }

    private var subtitle: String {
        if selectedCity != nil {
            return String(localized: "Später kannst du wechseln oder weitere dazunehmen.")
        }
        return String(localized: "Mehr Orte kannst du später dazunehmen.")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Ort suchen …", text: $searchText)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color(.secondarySystemBackground), in: .capsule)
    }

    @ViewBuilder private var resultsList: some View {
        if let searchError {
            ContentUnavailableView(
                "Suche fehlgeschlagen",
                systemImage: "wifi.exclamationmark",
                description: Text(searchError)
            )
        } else if !results.isEmpty {
            VStack(spacing: 0) {
                ForEach(results.prefix(5).enumerated(), id: \.element.id) { index, result in
                    VStack(spacing: 0) {
                        Button {
                            select(result)
                        } label: {
                            HStack {
                                Text(formatted(result))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if index < min(results.count, 5) - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                    .modifier(StaggeredRowAppearModifier(index: index))
                }
            }
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
            .catDash()
            .transition(.opacity)
        }
    }

    private func search() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            results = []
            searchError = nil
            return
        }

        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }

        do {
            let response = try await client.getGeocodeSearchResult(name: query)
            guard !Task.isCancelled else { return }
            searchError = nil
            results = response.results ?? []
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            searchError = error.localizedDescription
        }
    }

    private func select(_ result: Components.Schemas.Location) {
        locationService.city.addCity(searchResult: result)
        searchText = ""
        results = []
        searchFocused = false
    }

    private func formatted(_ location: Components.Schemas.Location) -> String {
        [location.name, location.admin3, location.admin1, location.country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private struct StaggeredRowAppearModifier: ViewModifier {
    let index: Int

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(.spring(duration: 0.45, bounce: 0.15).delay(Double(index) * 0.05)) {
                    shown = true
                }
            }
    }
}
