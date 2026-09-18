//
//  ClassicCardBack.swift
//  Oscar°
//
//  The flip side of the iOS 6 weather app: dark stage, a bar with "+",
//  "Wetter" and a blue "Fertig", a white list card in permanent edit mode
//  (red delete circles, drag grips), the big °F/°C switch, and the lockup
//  at the bottom. The "Einstellungen" button sits where Yahoo's logo used
//  to be and opens the modern settings.
//

import SwiftUI

struct ClassicCardBack: View {
    let onDone: () -> Void
    let onSettings: () -> Void

    @Bindable private var settingsService = SettingService.shared
    private let cityService = CityService.shared
    private let locationService = LocationService.shared
    @State private var showsLocations = false

    private var gpsAuthorized: Bool {
        locationService.authStatus == .authorizedWhenInUse || locationService.authStatus == .authorizedAlways
    }

    var body: some View {
        VStack(spacing: 12) {
            topBar
            placeList
            unitSwitch
            lockup
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(Color(white: 0.2))
        .sheet(isPresented: $showsLocations) {
            ClassicSearchView()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                showsLocations = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 36)
                    .background(classicBarButton(top: Color(white: 0.3), bottom: Color(white: 0.05)))
            }
            .accessibilityLabel(Text("Ort hinzufügen"))
            Spacer()
            Text("Wetter")
                .font(.custom("HelveticaNeue-Bold", fixedSize: 22))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 0, y: -1)
            Spacer()
            Button(action: onDone) {
                Text("Fertig")
                    .font(.custom("HelveticaNeue-Bold", fixedSize: 15))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(classicBarButton(top: Color(red: 0.45, green: 0.62, blue: 0.9), bottom: Color(red: 0.1, green: 0.35, blue: 0.8)))
            }
        }
        .frame(height: 48)
        .padding(.horizontal, -4)
    }

    private var placeList: some View {
        List {
            if gpsAuthorized {
                Section {
                    Label(cityService.currentLocationDisplayName, systemImage: "location.fill")
                }
            }
            Section {
                ForEach(cityService.cities, id: \.objectID) { city in
                    Text(city.displayName)
                }
                .onDelete(perform: cityService.deleteCity)
                .onMove(perform: cityService.moveCity)
            }
        }
        .font(.custom("HelveticaNeue-Bold", fixedSize: 22))
        .listStyle(.plain)
        .listSectionSpacing(0)
        .scrollContentBackground(.hidden)
        // iOS 6 kept the list permanently in edit mode: delete circles and
        // reorder grips always visible.
        .environment(\.editMode, .constant(.active))
        // White card under a dark stage: the list must not follow the dark
        // scheme the classic view sets.
        .environment(\.colorScheme, .light)
        .background(.white)
        .clipShape(.rect(cornerRadius: 10))
    }

    /// The big two-segment control from the original: the selected unit in
    /// blue, the other in light gray.
    private var unitSwitch: some View {
        HStack(spacing: 0) {
            unitSegment("°C", tag: "celsius")
            unitSegment("°F", tag: "fahrenheit")
        }
        .frame(height: 50)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Temperatur"))
    }

    private func unitSegment(_ label: String, tag: String) -> some View {
        let selected = settingsService.temperatureUnit == tag
        return Button {
            settingsService.temperatureUnit = tag
        } label: {
            Text(verbatim: label)
                .font(.custom("HelveticaNeue-Bold", fixedSize: 22))
                .foregroundStyle(selected ? .white : Color(white: 0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    selected
                        ? LinearGradient(colors: [Color(red: 0.55, green: 0.7, blue: 0.95), Color(red: 0.2, green: 0.45, blue: 0.9)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color(white: 0.98), Color(white: 0.85)], startPoint: .top, endPoint: .bottom)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var lockup: some View {
        Button(action: onSettings) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18))
                Text("Einstellungen")
                    .font(.custom("HelveticaNeue-Bold", fixedSize: 17))
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(height: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Einstellungen"))
    }
}

/// The glossy iOS 6 bar button, shared by the classic bars.
func classicBarButton(top: Color, bottom: Color) -> some View {
    RoundedRectangle(cornerRadius: 7)
        .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.25), lineWidth: 1))
}
