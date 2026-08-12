import CoreLocation
import SwiftUI

/// Display data for a saved city's marker: temperature + condition icon once
/// the batch conditions are in, the emoji/pin fallback before that.
struct CityMapChip: Equatable {
    var latitude: Double
    var longitude: Double
    var title: String
    var emoji: String?
    var temperature: Double?
    var iconAsset: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct LocationMapSheet: View {
    let cities: [City]
    let initialCenter: CLLocationCoordinate2D
    let onAdd: (LocationCandidate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: PickedPoint?
    @State private var pickCount = 0
    @State private var candidate: LocationCandidate?
    private var conditionsStore = CityConditionsStore.shared

    init(
        cities: [City],
        initialCenter: CLLocationCoordinate2D,
        onAdd: @escaping (LocationCandidate) -> Void
    ) {
        self.cities = cities
        self.initialCenter = initialCenter
        self.onAdd = onAdd
    }

    /// Live per-city chip data; the store publishes and the map re-syncs its
    /// annotations as conditions arrive.
    private var chips: [CityMapChip] {
        cities.map { city in
            let conditions = conditionsStore.conditions(
                for: CLLocationCoordinate2D(latitude: city.lat, longitude: city.lon)
            )
            return CityMapChip(
                latitude: city.lat,
                longitude: city.lon,
                title: city.displayName,
                emoji: city.emoji,
                temperature: conditions?.temperature,
                iconAsset: conditions?.iconAssetName
            )
        }
    }

    struct PickedPoint: Equatable {
        var latitude: Double
        var longitude: Double
        var name: String?
        var detail: String?
        /// Reverse geocoding still running: the card shows a spinner, never the
        /// raw coordinates (those remain only as the failure fallback).
        var isResolving = true

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        var coordinateText: String {
            String(format: "%.3f°, %.3f°", latitude, longitude)
        }
    }

    var body: some View {
        ZStack {
            MapLibreLocationPicker(
                chips: chips,
                initialCenter: initialCenter,
                pickedCoordinate: picked?.coordinate
            ) { coordinate in
                pick(coordinate)
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        UIApplication.shared.playHapticFeedback()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .accessibilityLabel(Text("Karte schließen"))
                }
                .padding(.trailing)
                .padding(.top)
                Spacer()
            }

        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let picked {
                    pickedCard(picked)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // What this screen is for — swapped out for the card the
                    // moment a pin is dropped.
                    ToastBanner(message: String(localized: "Tippe auf die Karte, um einen Ort hinzuzufügen."))
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                MapAttributionLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18)
                    .padding(.bottom, 2)
            }
        }
        .animation(.spring(duration: 0.35), value: picked)
        .sensoryFeedback(.impact(weight: .light), trigger: pickCount)
        .sheet(item: $candidate) { candidate in
            LocationPreviewSheet(candidate: candidate) {
                onAdd(candidate)
            }
        }
    }

    private func pickedCard(_ point: PickedPoint) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if point.isResolving && point.name == nil {
                    // Never flash raw coordinates while the geocoder works;
                    // they only remain as the failure fallback below.
                    ProgressView()
                        .controlSize(.small)
                        .frame(height: 20)
                } else {
                    Text(point.name ?? point.coordinateText)
                        .font(.headline)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                Text(point.detail ?? String(localized: "Gewählter Punkt"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                candidate = candidate(for: point)
            } label: {
                Text("Vorschau")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.blue)
            .disabled(point.isResolving && point.name == nil)
            Button {
                withAnimation(.spring(duration: 0.3)) { picked = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Auswahl aufheben"))
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func candidate(for point: PickedPoint) -> LocationCandidate {
        LocationCandidate(
            name: point.name ?? point.coordinateText,
            detail: point.detail,
            latitude: point.latitude,
            longitude: point.longitude
        )
    }

    private func pick(_ coordinate: CLLocationCoordinate2D) {
        pickCount += 1
        withAnimation(.spring(duration: 0.35)) {
            picked = PickedPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        Task {
            await resolveName(for: coordinate)
        }
    }

    /// Names the dropped pin via reverse geocoding; best-effort, the raw
    /// coordinates stay usable (and become the label) when it fails.
    private func resolveName(for coordinate: CLLocationCoordinate2D) async {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemark = try? await geocoder.reverseGeocodeLocation(location).first

        // A new tap may have replaced the pin while geocoding ran.
        guard var current = picked,
              current.latitude == coordinate.latitude,
              current.longitude == coordinate.longitude else {
            return
        }
        current.isResolving = false
        if let placemark {
            current.name = placemark.locality ?? placemark.name
            current.detail = [placemark.administrativeArea, placemark.country]
                .compactMap { $0 }
                .joined(separator: ", ")
            if current.detail?.isEmpty == true {
                current.detail = nil
            }
        }
        withAnimation(.snappy) {
            picked = current
        }
    }
}
