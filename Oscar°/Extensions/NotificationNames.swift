import Foundation

extension Notification.Name {
    /// A unit or format setting changed and weather data must be re-fetched.
    static let unitChanged = Notification.Name("UnitChanged")
    /// The selected city changed.
    static let cityToggle = Notification.Name("CityToggle")
    /// GPS location moved or authorization changed.
    static let changedLocation = Notification.Name("ChangedLocation")
}
