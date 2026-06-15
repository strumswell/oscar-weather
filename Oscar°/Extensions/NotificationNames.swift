import Foundation

extension Notification.Name {
    /// A unit or format setting changed and weather data must be re-fetched.
    static let unitChanged = Notification.Name("UnitChanged")
    /// The selected city changed.
    static let cityToggle = Notification.Name("CityToggle")
    /// GPS location moved or authorization changed.
    static let changedLocation = Notification.Name("ChangedLocation")
    /// A forced forecast model had no data for a location and best_match was used instead.
    /// `userInfo["modelName"]` carries the display name of the model that failed.
    static let forecastModelFallback = Notification.Name("ForecastModelFallback")
}
