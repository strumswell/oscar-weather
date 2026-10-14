//
//  ClassicWeatherView.swift
//  Oscar°
//
//  The iOS 6 weather app: one card per place on a black stage, swiped
//  horizontally, page dots underneath. Replaces the tab bar while the
//  classic theme is on (see RootTabView). The ⓘ flips the screen over to
//  the place list, which is also where the modern settings sheet is reached.
//  The logo in the card's footer opens the map with classic chrome.
//

import SwiftUI

struct ClassicWeatherView: View {
    @Environment(NowPresentationCoordinator.self) private var presentation
    @Environment(Location.self) private var location: Location
    @Environment(\.scenePhase) private var scenePhase
    private let store = ClassicForecastStore.shared
    @State private var page: ClassicPlace.ID = ""
    @State private var isFlipped = false
    @State private var showsMap = false
    @State private var flipAngle: Double = 0

    var body: some View {
        ZStack {
            front
                .opacity(isFlipped ? 0 : 1)
                .accessibilityHidden(isFlipped)
            ClassicCardBack(onDone: flip) {
                presentation.present(.settings)
            }
            .opacity(isFlipped ? 1 : 0)
            .accessibilityHidden(!isFlipped)
        }
        .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { await store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cityToggle)) { _ in
            Task { await store.refresh(onlyMissing: true) }
        }
        .onChange(of: store.places, initial: true) { _, places in
            if !places.contains(where: { $0.id == page }) { page = places.first?.id ?? "" }
        }
        .fullScreenCover(isPresented: $showsMap) {
            WeatherMapDetailView(settingsService: SettingService.shared, classicChrome: true) {
                showsMap = false
            }
        }
    }

    private func flip() {
        let direction: Double = isFlipped ? -1 : 1
        withAnimation(.easeIn(duration: 0.3)) {
            flipAngle = 90 * direction
        } completion: {
            var swap = Transaction()
            swap.disablesAnimations = true
            withTransaction(swap) {
                isFlipped.toggle()
                flipAngle = -90 * direction
            }
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.3)) { flipAngle = 0 }
            }
        }
    }

    private var front: some View {
        GeometryReader { geometry in
            let cardWidth = min(geometry.size.width, 460)
            let scale = (cardWidth - 32) / 288

            VStack(spacing: 12 * scale) {
                if store.places.isEmpty {
                    emptyState
                } else {
                    TabView(selection: $page) {
                        ForEach(store.places) { place in
                            ClassicWeatherCard(
                                title: title(for: place),
                                forecast: store.forecasts[place.id],
                                updatedAt: store.updatedAt,
                                scale: scale,
                                onInfo: flip,
                                onMap: { showsMap = true }
                            )
                            .padding(.horizontal, 16)
                            .frame(maxWidth: cardWidth)
                            .padding(.top, geometry.safeAreaInsets.top - 16 * scale)
                            .tag(place.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea(edges: .top)
                    dots
                }
            }
            .padding(.bottom, 6)
        }
    }

    private func title(for place: ClassicPlace) -> String {
        guard place.isCurrentLocation, CityService.shared.getSelectedCity() == nil, !location.name.isEmpty else {
            return place.title
        }
        return location.name
    }

    private var dots: some View {
        HStack(spacing: 10) {
            ForEach(store.places) { place in
                Group {
                    if place.isCurrentLocation {
                        Image(systemName: "location.fill")
                            .font(.system(size: 9))
                    } else {
                        Circle()
                            .frame(width: 7, height: 7)
                    }
                }
                .foregroundStyle(.white.opacity(place.id == page ? 1 : 0.35))
            }
        }
        .frame(height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Seite \(pageNumber) von \(store.places.count)"))
    }

    private var pageNumber: Int {
        (store.places.firstIndex { $0.id == page } ?? 0) + 1
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Keine Orte")
                .font(.title2.bold())
            Text("Füge einen Ort hinzu oder erlaube den Standortzugriff.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Orte verwalten", action: flip)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}

#Preview {
    ClassicWeatherView()
        .environment(Location())
        .environment(NowPresentationCoordinator())
}
