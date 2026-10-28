import Foundation

extension Notification.Name {
    static let weatherRefreshNeeded = Notification.Name("WeatherRefreshNeeded")
    static let unitsDidChange = Notification.Name("UnitsDidChange")
    static let cityToggle = Notification.Name("CityToggle")
    static let forecastModelFallback = Notification.Name("ForecastModelFallback")
    static let mapCenterOnUser = Notification.Name("MapCenterOnUser")
}
