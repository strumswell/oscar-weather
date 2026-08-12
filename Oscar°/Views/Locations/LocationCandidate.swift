import CoreLocation

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
