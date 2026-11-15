// The place a widget, control or intent shows: a saved city or the app's current place.
import CoreLocation
import Foundation

func currentWidgetCoordinates() async -> CLLocationCoordinate2D {
    await MainActor.run {
        LocationService.shared.update()
        return LocationService.shared.getCoordinates()
    }
}

struct WidgetPlace {
    let coordinates: CLLocationCoordinate2D
    var name: String? = nil
    var cityID: String? = nil

    var isFixed: Bool { name != nil }

    func locationName() async -> String {
        if let name { return name }
        return await LocationService.shared.getLocationName()
    }
}

#if os(iOS)
func widgetPlace(for cityID: String?) async -> WidgetPlace {
    if let cityID,
       let city = WidgetCity(id: cityID),
       !city.isCurrentLocation,
       city.latitude.isFinite,
       city.longitude.isFinite {
        return WidgetPlace(
            coordinates: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude),
            name: city.name,
            cityID: cityID
        )
    }
    return WidgetPlace(coordinates: await currentWidgetCoordinates())
}
#endif
