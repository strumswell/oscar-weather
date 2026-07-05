import Foundation

extension Notification.Name {
    /// A weather-data input changed — GPS location, selected city, a unit/format
    /// setting, or the forecast model — and the forecast must be re-fetched.
    /// Posted by the mutating service; NowView owns the single refresh handler.
    static let weatherRefreshNeeded = Notification.Name("WeatherRefreshNeeded")
    /// The saved-cities list changed (selection, order, membership).
    static let cityToggle = Notification.Name("CityToggle")
    /// A forced forecast model had no data for a location and best_match was used instead.
    /// `userInfo["modelName"]` carries the display name of the model that failed.
    static let forecastModelFallback = Notification.Name("ForecastModelFallback")
}
