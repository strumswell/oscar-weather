import SwiftUI

enum HourlyLens: String, CaseIterable, Identifiable {
    case overview
    case wind
    case humidity
    case pressure
    case clouds
    case soilTemperature
    case soilMoisture
    case evapotranspiration

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Überblick"
        case .wind: "Wind"
        case .humidity: "Luftfeuchtigkeit"
        case .pressure: "Luftdruck"
        case .clouds: "Wolken"
        case .soilTemperature: "Bodentemperatur"
        case .soilMoisture: "Bodenfeuchte"
        case .evapotranspiration: "Verdunstung"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .wind: "wind"
        case .humidity: "humidity"
        case .pressure: "barometer"
        case .clouds: "cloud"
        case .soilTemperature: "square.3.layers.3d"
        case .soilMoisture: "drop.halffull"
        case .evapotranspiration: "leaf"
        }
    }
}

extension Color {
    static let hourlyRain = Color.blue
    static let hourlyCloud = Color(white: 0.9)
}

struct HourlyLensLayout {
    struct Line {
        let values: [Double]
        let color: Color
        let width: CGFloat
        let label: String?
    }

    struct Band {
        let values: [Double]
        let centerFraction: CGFloat
        let label: String
    }

    let lines: [Line]
    let domain: ClosedRange<Double>
    let showsBars: Bool
    let barsAlpha: Double
    let extremes: [HourlyTimelineModel.ExtremeMark]
    let extremeFormat: (Double) -> String
    let primaryColor: Color
    var barsLabel: String? = nil
    var bands: [Band] = []
    var showsDirectionArrows = false

    var primary: Line? { lines.last }
}
