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

// MARK: - MapLibre map (representable)

/// The picker's map: the same MapLibre basemap as the weather map (same style
/// setting, same hidden-chrome/attribution arrangement, same user-location
/// dot), without any of its overlay layers.
struct MapLibreLocationPicker: UIViewRepresentable {
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
        // Adaptive compass (visible only while rotated), below the glass
        // close button in the top-right corner.
        mapView.compassView.compassVisibility = .adaptive
        mapView.compassViewPosition = .topRight
        mapView.compassViewMargins = CGPoint(x: 21, y: 80)

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
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
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
                // The callout repeats the identity line baked under the chip.
                pin.title = [chip.emoji ?? "", chip.title]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
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

        // MARK: Delegate (main-actor methods behind a @preconcurrency
        // conformance; MapLibre delivers its callbacks on the main thread)

        func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
            var result: MLNAnnotationImage?
            if let cityPin = annotation as? CityPinAnnotation, let chip = cityPin.chip {
                // Same identity line as the weather map's chips: the emoji
                // leads the name under the capsule.
                let identity = [chip.emoji ?? "", chip.title]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if let temperature = chip.temperature, let iconAsset = chip.iconAsset {
                    let temperatureText = "\(Int(temperature.rounded()))°"
                    let reuseID = "city-chip-\(iconAsset)-\(temperatureText)-\(identity)"
                    result = mapView.dequeueReusableAnnotationImage(withIdentifier: reuseID)
                        ?? MLNAnnotationImage(
                            image: MapChip.labeled(
                                MapChip.conditions(iconAsset: iconAsset, temperatureText: temperatureText),
                                label: identity,
                                balancedAnchor: true
                            ),
                            reuseIdentifier: reuseID
                        )
                } else {
                    // Conditions not in yet: the emoji/pin disc as fallback
                    // (emoji on the disc, only the name underneath).
                    let reuseID = "city-pin-\(chip.emoji ?? "plain")-\(chip.title)"
                    result = mapView.dequeueReusableAnnotationImage(withIdentifier: reuseID)
                        ?? MLNAnnotationImage(
                            image: MapChip.labeled(
                                MapChip.pin(emoji: chip.emoji),
                                label: chip.title,
                                balancedAnchor: true
                            ),
                            reuseIdentifier: reuseID
                        )
                }
            } else if annotation is PickedPinAnnotation {
                result = mapView.dequeueReusableAnnotationImage(withIdentifier: "picked-pin")
                    ?? MLNAnnotationImage(image: CityMarkerImage.make(), reuseIdentifier: "picked-pin")
            }
            return result
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard annotation is MLNUserLocation else { return nil }
            // Empty view suppresses the stock puck; the visible dot renders
            // in-style instead (UserLocationDot, below).
            return MLNUserLocationAnnotationView(reuseIdentifier: "user-location-hidden")
        }

        func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool {
            annotation is CityPinAnnotation
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            UserLocationDot.sync(style: style, coordinate: mapView.userLocation?.coordinate)
        }

        func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
            guard let style = mapView.style else { return }
            UserLocationDot.sync(style: style, coordinate: mapView.userLocation?.coordinate)
        }

    }
}

/// A saved city on the picker map.
private final class CityPinAnnotation: MLNPointAnnotation {
    var chip: CityMapChip?
}

/// The candidate marker dropped by a tap.
private final class PickedPinAnnotation: MLNPointAnnotation {}
