import Charts
import SwiftUI

struct StationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Weather.self) private var weather
    @State private var selectedID: String

    init(initialID: String) {
        _selectedID = State(initialValue: initialID)
    }

    var body: some View {
        let stations = weather.stations
        let station = stations.first { $0.id == selectedID } ?? stations.first
        NavigationStack {
            ScrollView {
                if let station {
                    let frame = StationChartFrame(end: station.last_report_at, weather: weather)
                    VStack(alignment: .leading, spacing: 16) {
                        if stations.count > 1 {
                            StationChips(stations: stations, selectedID: $selectedID)
                        }
                        StationHeader(
                            id: station.id,
                            name: station.name,
                            subtitle: [station.current.weather_code.map(WeatherConditionLabel.text(for:)),
                                       stationSubtitle(station, timeZone: weather.forecast.locationTimeZone, units: SettingService.shared.units),
                                       reportingInterval(station.history)].compactMap(\.self).joined(separator: " · "))
                        StationValueGrid(station: station)
                        Text("Letzte 24h")
                            .font(.title3.bold())
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 8)
                        StationTemperatureChart(history: station.history, frame: frame)
                        StationWindChart(history: station.history, frame: frame)
                        if station.precipitation_24h_mm != nil {
                            StationPrecipitationChart(
                                history: station.history, frame: frame, total: station.precipitation_24h_mm)
                        }
                        StationPressureChart(history: station.history, frame: frame)
                        StationFooter()
                    }
                    .padding()
                } else {
                    Text("Gerade keine Messwerte in der Nähe.")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .navigationTitle("Messstationen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close, action: dismiss.callAsFunction)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private func reportingInterval(_ history: [Components.Schemas.StationReading]) -> String? {
    let times = history.filter { $0.temperature_c != nil }.map(\.time)
    guard times.count > 2 else { return nil }
    let gaps = zip(times.dropFirst(), times).map { $0.timeIntervalSince($1) }.sorted()
    let typical = gaps[gaps.count / 2]
    let regular = gaps.filter { abs($0 - typical) <= typical * 0.2 }.count
    guard regular * 4 >= gaps.count * 3 else { return String(localized: "unregelmäßig") }
    let minutes = Int((typical / 60).rounded())
    switch minutes {
    case ..<50: return String(localized: "alle \(minutes) Min.")
    case 50..<90: return String(localized: "stündlich")
    default: return String(localized: "alle \(Int((Double(minutes) / 60).rounded())) Std.")
    }
}

private struct StationChips: View {
    let stations: [Components.Schemas.NearbyStation]
    @Binding var selectedID: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(stations) { station in
                    let selected = station.id == selectedID
                    Button {
                        selectedID = station.id
                    } label: {
                        Text(verbatim: "\(station.name) · \(SettingService.shared.units.distanceString(station.distance_km))")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(selected ? Color(uiColor: .systemBackground) : .primary)
                            .background(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.thinMaterial), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct StationHeader: View {
    let id: String
    let name: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                    .font(.title2.bold())
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            FavoriteStar(id: id)
        }
    }
}

private struct StationValueGrid: View {
    let station: Components.Schemas.NearbyStation

    var body: some View {
        let units = SettingService.shared.units
        let current = station.current
        let direction = current.wind_direction_deg.map { " \(compassDirection($0))" } ?? ""
        DetailCard {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 14) {
                StationValue(label: "Temperatur", value: units.preciseTemperatureString(current.temperature_c))
                StationValue(label: "Taupunkt", value: units.preciseTemperatureString(current.dew_point_c))
                StationValue(label: "Luftfeuchtigkeit", value: current.humidity_pct.map { "\(Int($0.rounded())) %" } ?? "–")
                StationValue(label: "Wind", value: units.windString(current.wind_speed_ms.map { $0 * 3.6 }) + direction)
                StationValue(label: "Böen", value: units.windString(current.wind_gust_ms.map { $0 * 3.6 }))
                StationValue(label: "Luftdruck", value: units.pressureString(current.pressure_hpa))
            }
        }
    }
}

private struct StationValue: View {
    let label: LocalizedStringResource
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StationFooter: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Gemessene Werte der nächstgelegenen Wetterstationen, keine Vorhersage.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 22) {
                ProviderLogo(asset: "logo-eumetnet", height: 28)
                ProviderLogo(asset: "logo-dwd", height: 28)
                ProviderLogo(asset: "logo-oscar-server", height: 24)
            }
            .foregroundStyle(.white)
            .opacity(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "EUMETNET, DWD & Oscar Server"))
        }
        .padding(.top, 8)
    }
}
