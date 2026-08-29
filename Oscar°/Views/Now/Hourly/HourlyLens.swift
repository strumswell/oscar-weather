import SwiftUI

/// One row of the deck card. Every lens is always on screen as a row showing
/// its live value at the scrubbed hour; the expanded row carries the chart.
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
    /// Every precipitation-blue in the sheet (bars, dots, badge, ET₀) shares it.
    static let hourlyRain = Color.blue
    static let hourlyCloud = Color(white: 0.9)
}

/// Everything the strip needs to render one lens: the line stack (the LAST
/// entry is the primary the playhead rides), a shared y-domain, bar/fill
/// flags, and the per-day extreme marks.
struct HourlyLensLayout {
    struct Line {
        let values: [Double]
        let color: Color
        let width: CGFloat
        let dashed: Bool
        let opacity: Double
        /// Row label in the playhead readout box; nil keeps the row
        /// value-only. The box rows double as the legend.
        let label: String?
    }

    /// Cloud lens: a coverage ribbon at a fixed altitude row, thickness
    /// modulated by cover — same idea as the meteogram's cloud ribbons.
    struct Band {
        let values: [Double]
        let centerFraction: CGFloat
        let label: String
    }

    let lines: [Line]
    let domain: ClosedRange<Double>
    let showsBars: Bool
    let barsAlpha: Double
    let fillsPrimary: Bool
    let extremes: [HourlyTimelineModel.ExtremeMark]
    /// Formats a value with its unit ("12°C", "34 km/h") — used by the
    /// gridline labels, the extreme marks, and the readout box alike.
    let extremeFormat: (Double) -> String
    let primaryColor: Color
    /// The precipitation bars' row label in the readout box ("Regen").
    var barsLabel: String? = nil
    var bands: [Band] = []
    /// Wind lens: direction arrows along the top of the strip.
    var showsDirectionArrows = false

    var primary: Line? { lines.last }
}
