//
//  LocationMapPicker.swift
//  Oscar°
//
//  Fullscreen map for picking a place, on the app's MapLibre basemap: saved
//  cities as emoji pins, a tap anywhere drops the city marker, and the bottom
//  card offers the tapped place for preview/adding.
//

import CoreLocation
import MapLibre
import SwiftUI
import UIKit

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

// MARK: - MapLibre map (representable)

/// The picker's map: the same MapLibre basemap as the weather map (same style
/// setting, same hidden-chrome/attribution arrangement, same user-location
/// dot), without any of its overlay layers.
private struct MapLibreLocationPicker: UIViewRepresentable {
    let chips: [CityMapChip]
    let initialCenter: CLLocationCoordinate2D
    var pickedCoordinate: CLLocationCoordinate2D?
    let onPick: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: SettingService.shared.mapBasemapStyle.styleURL)
        mapView.delegate = context.coordinator
        mapView.setCenter(initialCenter, zoomLevel: 7, animated: false)
        mapView.allowsTilting = false
        // Never triggers the system prompt: enabled only once access exists.
        mapView.showsUserLocation = WeatherMapView.locationAuthorized
        // Attribution is the visible MapAttributionLabel corner credit;
        // MapLibre's ⓘ button and wordmark stay hidden (see WeatherMapView).
        mapView.logoView.isHidden = true
        mapView.attributionButton.isHidden = true
        mapView.compassView.isHidden = true

        // The map's own tap recognizers (annotation selection, double-tap zoom)
        // must fail before a tap counts as "drop a pin here".
        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleMapTap(_:)))
        for recognizer in mapView.gestureRecognizers ?? []
        where recognizer is UITapGestureRecognizer {
            tap.require(toFail: recognizer)
        }
        mapView.addGestureRecognizer(tap)

        context.coordinator.mapView = mapView
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncAnnotations()
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapLibreLocationPicker
        weak var mapView: MLNMapView?
        private var cityAnnotations: [CityPinAnnotation] = []
        private var citySignature: String?
        private var pickedAnnotation: PickedPinAnnotation?

        init(_ parent: MapLibreLocationPicker) {
            self.parent = parent
        }

        @objc func handleMapTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let mapView else { return }
            let coordinate = mapView.convert(gesture.location(in: mapView), toCoordinateFrom: mapView)
            parent.onPick(coordinate)
        }

        func syncAnnotations() {
            syncCityPins()
            syncPickedPin()
        }

        private func syncCityPins() {
            guard let mapView else { return }
            let signature = parent.chips
                .map {
                    "\($0.latitude)|\($0.longitude)|\($0.emoji ?? "")|\($0.title)"
                        + "|\($0.temperature.map { Int($0.rounded()) } ?? .min)|\($0.iconAsset ?? "")"
                }
                .joined(separator: ";")
            guard signature != citySignature else { return }
            citySignature = signature

            if !cityAnnotations.isEmpty {
                mapView.removeAnnotations(cityAnnotations)
            }
            cityAnnotations = parent.chips.map { chip in
                let pin = CityPinAnnotation()
                pin.coordinate = chip.coordinate
                pin.title = chip.title
                pin.chip = chip
                return pin
            }
            mapView.addAnnotations(cityAnnotations)
        }

        private func syncPickedPin() {
            guard let mapView else { return }
            guard let coordinate = parent.pickedCoordinate else {
                if let pickedAnnotation {
                    mapView.removeAnnotation(pickedAnnotation)
                    self.pickedAnnotation = nil
                }
                return
            }
            if let pickedAnnotation {
                if pickedAnnotation.coordinate.latitude != coordinate.latitude
                    || pickedAnnotation.coordinate.longitude != coordinate.longitude {
                    pickedAnnotation.coordinate = coordinate
                }
            } else {
                let pin = PickedPinAnnotation()
                pin.coordinate = coordinate
                mapView.addAnnotation(pin)
                pickedAnnotation = pin
            }
        }

        // MARK: Delegate (delegate callbacks arrive on the main thread; the
        // `nonisolated(unsafe)` locals only ferry non-Sendable values across
        // `assumeIsolated`, same as WeatherMapView)

        nonisolated func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
            nonisolated(unsafe) var result: MLNAnnotationImage?
            nonisolated(unsafe) let annotation = annotation
            MainActor.assumeIsolated {
                if let cityPin = annotation as? CityPinAnnotation, let chip = cityPin.chip {
                    if let temperature = chip.temperature, let iconAsset = chip.iconAsset {
                        let temperatureText = "\(Int(temperature.rounded()))°"
                        let reuseID = "city-chip-\(iconAsset)-\(temperatureText)"
                        result = mapView.dequeueReusableAnnotationImage(withIdentifier: reuseID)
                            ?? MLNAnnotationImage(
                                image: CityChipImage.chip(iconAsset: iconAsset, temperatureText: temperatureText),
                                reuseIdentifier: reuseID
                            )
                    } else {
                        // Conditions not in yet: the emoji/pin disc as fallback.
                        let reuseID = "city-pin-\(chip.emoji ?? "plain")"
                        result = mapView.dequeueReusableAnnotationImage(withIdentifier: reuseID)
                            ?? MLNAnnotationImage(
                                image: CityChipImage.pin(emoji: chip.emoji),
                                reuseIdentifier: reuseID
                            )
                    }
                } else if annotation is PickedPinAnnotation {
                    result = mapView.dequeueReusableAnnotationImage(withIdentifier: "picked-pin")
                        ?? MLNAnnotationImage(image: CityMarkerImage.make(), reuseIdentifier: "picked-pin")
                }
            }
            return result
        }

        nonisolated func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            nonisolated(unsafe) var result: MLNAnnotationView?
            nonisolated(unsafe) let annotation = annotation
            MainActor.assumeIsolated {
                guard annotation is MLNUserLocation else { return }
                // Empty view suppresses the stock puck; the visible dot renders
                // in-style instead (UserLocationDot, below).
                result = MLNUserLocationAnnotationView(reuseIdentifier: "user-location-hidden")
            }
            return result
        }

        nonisolated func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool {
            annotation is CityPinAnnotation
        }

        nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            nonisolated(unsafe) let style = style
            MainActor.assumeIsolated {
                UserLocationDot.sync(style: style, coordinate: mapView.userLocation?.coordinate)
            }
        }

        nonisolated func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
            MainActor.assumeIsolated {
                guard let style = mapView.style else { return }
                UserLocationDot.sync(style: style, coordinate: mapView.userLocation?.coordinate)
            }
        }

    }
}

// MARK: - City chip images

/// Shared renderer for saved-city map markers: the conditions capsule and the
/// emoji/pin disc fallback. Drawn identically on the picker map (annotation
/// images) and the weather map (style images for the chips symbol layer).
@MainActor
enum CityChipImage {
    /// A saved city's conditions as a capsule chip: the app's own weather icon
    /// (01d…50n assets, same set as the forecast lists) + current temperature,
    /// like a mini weather-map station label. A custom emoji, when set, leads
    /// the capsule.
    static func chip(iconAsset: String, temperatureText: String, emoji: String? = nil) -> UIImage {
        let height: CGFloat = 28
        let padding: CGFloat = 8
        let spacing: CGFloat = 4

        let icon = UIImage(named: iconAsset)
        let iconSize = CGSize(width: 21, height: 21)

        let emojiText: NSAttributedString? = (emoji?.isEmpty == false)
            ? NSAttributedString(string: emoji ?? "", attributes: [.font: UIFont.systemFont(ofSize: 13)])
            : nil

        let text = NSAttributedString(
            string: temperatureText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
        )
        let textSize = text.size()
        let emojiSize = emojiText?.size() ?? .zero
        let emojiAdvance = emojiText == nil ? 0 : emojiSize.width + spacing
        let width = padding + emojiAdvance + iconSize.width + spacing + textSize.width + padding

        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            let capsule = UIBezierPath(
                roundedRect: CGRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1),
                cornerRadius: (height - 1) / 2
            )
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: 3,
                color: UIColor.black.withAlphaComponent(0.35).cgColor
            )
            UIColor(white: 0.13, alpha: 0.92).setFill()
            capsule.fill()
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor(white: 1, alpha: 0.35).setStroke()
            capsule.lineWidth = 1
            capsule.stroke()

            emojiText?.draw(at: CGPoint(
                x: padding,
                y: (height - emojiSize.height) / 2
            ))
            icon?.draw(in: CGRect(
                x: padding + emojiAdvance,
                y: (height - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            ))
            text.draw(at: CGPoint(
                x: padding + emojiAdvance + iconSize.width + spacing,
                y: (height - textSize.height) / 2
            ))
        }
    }

    /// A saved city as a small dark disc with its emoji (or a red pin glyph
    /// when none is set) — the fallback while conditions are still loading.
    static func pin(emoji: String?) -> UIImage {
        let size = CGSize(width: 32, height: 32)
        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            let circle = UIBezierPath(ovalIn: rect)
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: 3,
                color: UIColor.black.withAlphaComponent(0.35).cgColor
            )
            UIColor(white: 0.13, alpha: 0.92).setFill()
            circle.fill()
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor(white: 1, alpha: 0.35).setStroke()
            circle.lineWidth = 1
            circle.stroke()

            if let emoji, !emoji.isEmpty {
                let text = NSAttributedString(
                    string: emoji,
                    attributes: [.font: UIFont.systemFont(ofSize: 15)]
                )
                let textSize = text.size()
                text.draw(at: CGPoint(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2
                ))
            } else {
                let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
                if let glyph = UIImage(systemName: "mappin", withConfiguration: config)?
                    .withTintColor(.systemRed, renderingMode: .alwaysOriginal) {
                    glyph.draw(in: CGRect(
                        x: (size.width - glyph.size.width) / 2,
                        y: (size.height - glyph.size.height) / 2,
                        width: glyph.size.width,
                        height: glyph.size.height
                    ))
                }
            }
        }
    }
}

/// A saved city on the picker map.
private final class CityPinAnnotation: MLNPointAnnotation {
    var chip: CityMapChip?
}

/// The candidate marker dropped by a tap.
private final class PickedPinAnnotation: MLNPointAnnotation {}
