import CoreLocation
import Observation

@MainActor
@Observable
class Location {
    var coordinates: CLLocationCoordinate2D
    var name: String
    var countryCode: String?

    init() {
        coordinates = CLLocationCoordinate2D(latitude: 52.52, longitude: 13.4)
        name = ""
        countryCode = nil
    }
}
