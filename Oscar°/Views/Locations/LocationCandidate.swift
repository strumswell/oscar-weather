import CoreLocation

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
