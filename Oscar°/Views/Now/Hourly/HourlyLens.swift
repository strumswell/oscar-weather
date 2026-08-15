import SwiftUI

/// The variable the timeline strip currently shows. One shared timeline,
/// swappable focus: switching lenses never moves the playhead or the window.
enum HourlyLens: String, CaseIterable, Identifiable {
    case overview
    case temperature
    case precipitation
    case wind
    case pressure
    case humidity
    case clouds
    case soilTemperature
    case soilMoisture
    case evapotranspiration

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Überblick"
        case .temperature: "Temperatur"
        case .precipitation: "Regen"
        case .wind: "Wind"
        case .pressure: "Druck"
        case .humidity: "Feuchte"
        case .clouds: "Wolken"
        case .soilTemperature: "Boden"
        case .soilMoisture: "Bodenfeuchte"
        case .evapotranspiration: "Verdunstung"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .temperature: "thermometer.medium"
        case .precipitation: "cloud.rain"
        case .wind: "wind"
        case .pressure: "barometer"
        case .humidity: "humidity"
        case .clouds: "cloud"
        case .soilTemperature: "square.3.layers.3d"
        case .soilMoisture: "drop.halffull"
        case .evapotranspiration: "leaf"
        }
    }
}

extension Color {
    /// Rain's darkened blue reads on the light day frost; every
    /// precipitation-blue in the sheet (bars, dots, badge, ET₀) shares it.
    static let hourlyRain = Color.blue.mix(with: .black, by: 0.2)
    static let hourlyCloud = Color(white: 0.9)
}

/// Series swatch shared by the strip legend and the readout chips: solid or
/// dashed line sample, or a bar chip.
struct HourlySeriesSwatch: View {
    let color: Color?
    let kind: HourlyTimelineModel.HUDSwatch

    var body: some View {
        if let color {
            switch kind {
            case .bar:
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 6, height: 12)
            case .line(let dashed):
                Group {
                    if dashed {
                        HStack(spacing: 2) {
                            Capsule().fill(color).frame(width: 5, height: 2.5)
                            Capsule().fill(color).frame(width: 5, height: 2.5)
                        }
                    } else {
                        Capsule().fill(color).frame(width: 12, height: 2.5)
                    }
                }
                .frame(height: 12)
            case .none:
                EmptyView()
            }
        }
    }
}

/// Everything the strip needs to render one lens: the line stack (the LAST
/// entry is the primary the playhead rides), a shared y-domain, bar/fill
/// flags, unit labels, and the per-day extreme marks.
struct HourlyLensLayout {
    struct Line {
        let values: [Double]
        let color: Color
        let width: CGFloat
        let dashed: Bool
        let opacity: Double
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
    let topLabel: String?
    let bottomLabel: String?
    let extremes: [HourlyTimelineModel.ExtremeMark]
    let extremeFormat: (Double) -> String
    /// Rain lens: extremes and the playhead ride the bar tops, not a line.
    let ridesBars: Bool
    let primaryColor: Color
    var bands: [Band] = []
    /// Wind lens: direction arrows along the top of the strip.
    var showsDirectionArrows = false

    var primary: Line? { lines.last }
}
