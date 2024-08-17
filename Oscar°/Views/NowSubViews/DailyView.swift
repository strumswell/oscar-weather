import SwiftUI

struct DailyView: View {
    @Environment(Weather.self) private var weather: Weather
    
    var body: some View {
        // Cap at 12 days to keep View from getting too large with too much (unreliable) data
        let dayNumber = (weather.forecast.daily?.time.count ?? 1) > 12 ? 12 : (weather.forecast.daily?.time.count ?? 1)
        let minTemp = weather.forecast.daily?.temperature_2m_min?.min() ?? 0.0
        let maxTemp = weather.forecast.daily?.temperature_2m_max?.max() ?? 40.0
        let heading = String.localizedStringWithFormat(NSLocalizedString("%d-Tage", comment: "Headline for Daily View"), dayNumber)
        let temperatureUnit = weather.forecast.daily_units?.temperature_2m_min ?? "°C"
        let precipitationUnit = weather.forecast.daily_units?.precipitation_sum ?? "mm"

        VStack(alignment: .leading) {
            Text(heading)
                .font(.title3)
                .bold()
                .foregroundColor(Color(UIColor.label))
                .padding([.leading, .top, .bottom])
            
            if weather.forecast.daily?.time == nil && weather.isLoading {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Spacer()
                    }
                    Spacer()
                }
                .frame(
                      minWidth: 0,
                      maxWidth: .infinity,
                      minHeight: 400,
                      maxHeight: 400,
                      alignment: .topLeading
                    )
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(.thinMaterial)
                .cornerRadius(10)
                .font(.system(size: 18))
                .padding([.leading, .trailing])
            } else {
                VStack {
                    ForEach(0...dayNumber-1, id: \.self) { dayPos in
                        let dayMinTemp = weather.forecast.daily?.temperature_2m_min?[dayPos]
                        let dayMaxTemp = weather.forecast.daily?.temperature_2m_max?[dayPos]
                        HStack {
                            Text(getWeekDay(timestamp: weather.forecast.daily?.time[dayPos] ?? 0.0))
                                .foregroundColor(Color(UIColor.label))
                                .bold()
                                .frame(width: 50, alignment: .leading)
                            Image(getWeatherIcon(pos: dayPos))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                            VStack {
                                Text("\(weather.forecast.daily?.precipitation_sum?[dayPos] ?? 0, specifier: "%.1f") \(precipitationUnit)")
                                    .font(.caption)
                                    .foregroundColor(Color(UIColor.label))
                                Text("\(weather.forecast.daily?.precipitation_probability_max?[dayPos] ?? 0, specifier: "%.0f") %")
                                    .font(.caption)
                                    .foregroundColor(Color(UIColor.secondaryLabel))
                            }
                                .frame(width: 60)
                            Text(roundTemperatureString(temperature: dayMinTemp))
                                .frame(width: 37, alignment: .trailing)
                            TemperatureRangeView(low: Int(dayMinTemp?.rounded() ?? 0), high: Int(dayMaxTemp?.rounded() ?? 0), minTemp: Int(minTemp.rounded()), maxTemp: Int(maxTemp.rounded()), unit: temperatureUnit)
                                .frame(height: 5)
                            Text(roundTemperatureString(temperature: dayMaxTemp))
                                .frame(width: 37, alignment: .leading)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.thinMaterial)
                .cornerRadius(10)
                .font(.system(size: 18))
                .padding([.leading, .trailing])
            }
        }
        .scrollTransition { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.8)
                .scaleEffect(phase.isIdentity ? 1 : 0.99)
                .blur(radius: phase.isIdentity ? 0 : 0.5)
        }
    }
}

extension DailyView {
    public func getWeekDay(timestamp: Double) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(secondsFromGMT: weather.forecast.utc_offset_seconds ?? 0) ?? TimeZone.current
        dateFormatter.dateFormat = "E"
        return dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }
    
    public func getWeatherIcon(pos: Int) -> String {
        switch weather.forecast.daily?.weathercode?[pos] ?? 0 {
        case 0, 1:
            return "01d"
        case 2:
            return "02d"
        case 3:
            return "04d"
        case 45, 48:
            return "50d"
        case 51:
            return "10d"
        case 71, 73, 75, 77:
            return "13d"
        case 95, 96, 99:
            return "11d"
        default:
            return "09d"
        }
    }
}

struct TemperatureRangeView: View {
    let low: Int
    let high: Int
    let minTemp: Int
    let maxTemp: Int
    let unit: String

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let lowPosition = position(for: low, in: width)
            let highPosition = position(for: high, in: width)
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: width, height: 4)
                Capsule()
                    .fill(gradient(for: low, high: high))
                    .frame(width: highPosition - lowPosition, height: 4)
                    .offset(x: lowPosition)
            }
            .alignmentGuide(VerticalAlignment.center) { d in d[VerticalAlignment.center] }
        }
    }

    func position(for temperature: Int, in width: CGFloat) -> CGFloat {
        let scale = CGFloat(temperature - minTemp) / CGFloat(maxTemp - minTemp)
        return scale * width
    }
    
    func gradient(for low: Int, high: Int) -> LinearGradient {
        let lowColor = color(for: low, unit: unit)
        let highColor = color(for: high, unit: unit)
        return LinearGradient(gradient: Gradient(colors: [lowColor, highColor]), startPoint: .leading, endPoint: .trailing)
    }
    
    func color(for temperature: Int, unit: String) -> Color {
        switch unit {
        case "°C":
            return colorForCelsius(temperature)
        case "°F":
            return colorForFahrenheit(temperature)
        case "K":
            return colorForKelvin(temperature)
        default:
            return colorForCelsius(temperature) // Default to Celsius if unit is unknown
        }
    }
    
    private func colorForCelsius(_ temperature: Int) -> Color {
        switch temperature {
        case ..<0:
            return .blue
        case 0..<10:
            return .green
        case 10..<20:
            return .yellow
        case 20..<30:
            return .orange
        case 30...:
            return .red
        default:
            return .purple
        }
    }
    
    private func colorForFahrenheit(_ temperature: Int) -> Color {
        switch temperature {
        case ..<32:
            return .blue
        case 32..<50:
            return .green
        case 50..<68:
            return .yellow
        case 68..<86:
            return .orange
        case 86...:
            return .red
        default:
            return .purple
        }
    }
    
    private func colorForKelvin(_ temperature: Int) -> Color {
        switch temperature {
        case ..<273:
            return .blue
        case 273..<283:
            return .green
        case 283..<293:
            return .yellow
        case 293..<303:
            return .orange
        case 303...:
            return .red
        default:
            return .purple
        }
    }
}
