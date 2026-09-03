import Foundation

struct WidgetCity: Identifiable {
    static let currentLocationID = "current"
    private static let legacyCurrentLocationID = "__current__"
    private static let coordinateScale = 100_000.0

    var id: String
    var name: String
    var latitude: Double
    var longitude: Double

    var isCurrentLocation: Bool {
        id == Self.currentLocationID || id == Self.legacyCurrentLocationID
    }

    static var currentLocation: WidgetCity {
        WidgetCity(
            id: currentLocationID,
            name: String(localized: "Aktueller Standort"),
            latitude: .nan,
            longitude: .nan
        )
    }

    init(id: String, name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    /// The identifier encodes the coordinates *and* name so the selection can be reconstructed
    /// from the id alone — see `init?(id:)`.
    static func makeID(latitude: Double, longitude: Double, name: String) -> String {
        "city_\(coordinateToken(latitude))_\(coordinateToken(longitude))_\(encodeName(name))"
    }

    /// Rebuilds a city straight from its identifier. Widget timeline resolution must not depend
    /// on a fresh Core Data read, because WidgetKit can run it in a separate process after the
    /// configuration UI has already closed.
    init?(id: String) {
        if id == Self.currentLocationID || id == Self.legacyCurrentLocationID {
            self = .currentLocation
            return
        }

        if let decoded = Self.decodeCurrentID(id) {
            self = decoded
            return
        }

        // Compatibility with older widget configurations that stored "lat,lon,name".
        let parts = id.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]) else {
            return nil
        }
        let name = parts.count >= 3 && !parts[2].isEmpty
            ? String(parts[2])
            : String(localized: "Ausgewählter Ort")
        self.init(id: id, name: name, latitude: latitude, longitude: longitude)
    }

    private static func decodeCurrentID(_ id: String) -> WidgetCity? {
        let parts = id.split(separator: "_", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts[0] == "city",
              let latitude = coordinate(from: String(parts[1])),
              let longitude = coordinate(from: String(parts[2])),
              let name = decodeName(String(parts[3])) else {
            return nil
        }

        return WidgetCity(id: id, name: name, latitude: latitude, longitude: longitude)
    }

    private static func coordinateToken(_ value: Double) -> String {
        let scaled = Int((value * coordinateScale).rounded())
        return scaled < 0 ? "m\(-scaled)" : "p\(scaled)"
    }

    private static func coordinate(from token: String) -> Double? {
        guard let prefix = token.first else { return nil }
        let number = token.dropFirst()
        guard let scaled = Int(number) else { return nil }

        switch prefix {
        case "p":
            return Double(scaled) / coordinateScale
        case "m":
            return -Double(scaled) / coordinateScale
        default:
            return nil
        }
    }

    private static func encodeName(_ name: String) -> String {
        Data(name.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeName(_ token: String) -> String? {
        var base64 = token
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: padding))
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
