import Foundation
import SwiftUI
// MARK: - Welcome
struct AQIResponse: Codable {
    let latitude, longitude, generationtimeMS: Double
    let utcOffsetSeconds: Int
    let timezone, timezoneAbbreviation: String
    let hourlyUnits: AQIHourlyUnits
    let hourly: AQIHourly

    enum CodingKeys: String, CodingKey {
        case latitude, longitude
        case generationtimeMS = "generationtime_ms"
        case utcOffsetSeconds = "utc_offset_seconds"
        case timezone
        case timezoneAbbreviation = "timezone_abbreviation"
        case hourlyUnits = "hourly_units"
        case hourly
    }
}

// MARK: - Hourly
struct AQIHourly: Codable {
    let time: [String]
    let europeanAqi, europeanAqiPm25, europeanAqiPm10, europeanAqiNo2: [Int?]
    let europeanAqiO3, europeanAqiSo2: [Int?]
    let uvIndex: [Double?]

    enum CodingKeys: String, CodingKey {
        case time
        case europeanAqi = "european_aqi"
        case europeanAqiPm25 = "european_aqi_pm2_5"
        case europeanAqiPm10 = "european_aqi_pm10"
        case europeanAqiNo2 = "european_aqi_no2"
        case europeanAqiO3 = "european_aqi_o3"
        case europeanAqiSo2 = "european_aqi_so2"
        case uvIndex = "uv_index"
    }
    
    public func getCurrentHour() -> Int {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour], from: now)
        return components.hour!
    }
    
    public func getColorForAQI(aqi: Int) -> Color {
        switch aqi {
        case let x where x <= 20:
            return .green
        case let x where x > 20 && x <= 40:
            return .orange
        case let x where x > 40 && x <= 60:
            return .orange
        case let x where x > 60 && x <= 80:
            return .red
        case let x where x > 80:
            return .purple
        default:
            return .gray
        }
    }
    
    public func getColorForUVI(uvi: Double) -> Color {
        switch uvi {
        case let x where x < 1:
            return .green
        case let x where x >= 1 && x < 2.5:
            return .green
        case let x where x >= 2.5 && x < 5.5:
            return .orange
        case let x where x >= 5.5 && x < 7.5:
            return .orange
        case let x where x >= 7.5 && x < 10.5:
            return .orange
        case let x where x >= 10.5:
            return .purple
        default:
            return .gray
        }
    }
}

// MARK: - HourlyUnits
struct AQIHourlyUnits: Codable {
    let time, europeanAqi, europeanAqiPm25, europeanAqiPm10: String
    let europeanAqiNo2, europeanAqiO3, europeanAqiSo2, uvIndex: String

    enum CodingKeys: String, CodingKey {
        case time
        case europeanAqi = "european_aqi"
        case europeanAqiPm25 = "european_aqi_pm2_5"
        case europeanAqiPm10 = "european_aqi_pm10"
        case europeanAqiNo2 = "european_aqi_no2"
        case europeanAqiO3 = "european_aqi_o3"
        case europeanAqiSo2 = "european_aqi_so2"
        case uvIndex = "uv_index"
    }
}
