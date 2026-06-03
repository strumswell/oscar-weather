import CoreData
import SwiftUI
import Combine

enum TimeFormatPreference: String, CaseIterable, Identifiable {
    case system
    case h24
    case h12

    var id: String { rawValue }

    var resolvedAPIValue: String {
        switch self {
        case .system:
            return Self.systemResolvedAPIValue
        case .h24:
            return "h24"
        case .h12:
            return "h12"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .system:
            return "System"
        case .h24:
            return "24 Stunden"
        case .h12:
            return "12 Stunden"
        }
    }

    static var systemResolvedAPIValue: String {
        let dateFormat = DateFormatter.dateFormat(
            fromTemplate: "j",
            options: 0,
            locale: .autoupdatingCurrent
        ) ?? ""
        return dateFormat.contains("a") ? "h12" : "h24"
    }
}

public class SettingService: ObservableObject {
    @Published var settings: Settings?
    private let context: NSManagedObjectContext
    private let pc = PersistenceController.shared
    private let nc = NotificationCenter.default
    private static let timeFormatPreferenceKey = "timeFormatPreference"
    private static let dailyForecastDaytimeTemperaturesEnabledKey = "dailyForecastDaytimeTemperaturesEnabled"
    private static let dailyForecastDaytimeTemperatureDisplayModeKey = "dailyForecastDaytimeTemperatureDisplayMode"
    private static let dailyForecastDaytimeTemperatureRangeModeKey = "dailyForecastDaytimeTemperatureRangeMode"
    private static let dailyForecastDaytimeCustomStartHourKey = "dailyForecastDaytimeCustomStartHour"
    private static let dailyForecastDaytimeCustomEndHourKey = "dailyForecastDaytimeCustomEndHour"
    private static let defaults = UserDefaults(suiteName: "group.cloud.bolte.Oscar") ?? .standard

    init() {
        self.context = pc.container.viewContext
        self.update()
    }
    
    func save() {
        do {
            try self.context.save()
            update()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    private func update() {
        do {
            let fetchRequest: NSFetchRequest<Settings>
            fetchRequest = Settings.fetchRequest()
            let result = try self.context.fetch(fetchRequest)
            
            // Create default settings if empty
            if (result.count < 1) {
                let defaultSettings = Settings(context: self.context)
                defaultSettings.druckLayer = false
                defaultSettings.dwdLayer = true
                defaultSettings.rainviewerLayer = false
                defaultSettings.infrarotLayer = false
                defaultSettings.tempLayer = false
                defaultSettings.humidityLayer = false
                defaultSettings.windDirectionLayer = false
                defaultSettings.temperatureUnit = "celsius"
                defaultSettings.windSpeedUnit = "kmh"
                defaultSettings.precipitationUnit = "mm"
                self.save()
            } else {
                self.settings = result.first!
            }
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    var oscarRadarLayer: Bool {
        get { UserDefaults.standard.bool(forKey: "oscarRadarLayer") }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "oscarRadarLayer")
        }
    }

    /// Raw storage for the active tile layer key (ICON-D2 or GFS).
    /// Use the `activeTileLayer: WeatherTileLayer?` extension accessor on iOS.
    var activeTileLayerRaw: String? {
        get { UserDefaults.standard.string(forKey: "activeTileLayer") }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "activeTileLayer")
        }
    }

    func updateTemperatureUnit(_ unit: String) {
        settings?.temperatureUnit = unit
        save()
        nc.post(name: Notification.Name("UnitChanged"), object: nil)
    }
    
    func updateWindSpeedUnit(_ unit: String) {
        settings?.windSpeedUnit = unit
        save()
        nc.post(name: Notification.Name("UnitChanged"), object: nil)
    }
    
    func updatePrecipitationUnit(_ unit: String) {
        settings?.precipitationUnit = unit
        save()
        nc.post(name: Notification.Name("UnitChanged"), object: nil)
    }

    var timeFormatPreference: TimeFormatPreference {
        get {
            let rawValue = Self.defaults.string(forKey: Self.timeFormatPreferenceKey)
            return TimeFormatPreference(rawValue: rawValue ?? "") ?? .system
        }
        set {
            objectWillChange.send()
            Self.defaults.set(newValue.rawValue, forKey: Self.timeFormatPreferenceKey)
            nc.post(name: Notification.Name("UnitChanged"), object: nil)
        }
    }

    var dailyForecastDaytimeTemperaturesEnabled: Bool {
        get {
            Self.defaults.bool(forKey: Self.dailyForecastDaytimeTemperaturesEnabledKey)
        }
        set {
            objectWillChange.send()
            Self.defaults.set(newValue, forKey: Self.dailyForecastDaytimeTemperaturesEnabledKey)
            nc.post(name: Notification.Name("UnitChanged"), object: nil)
        }
    }

    var dailyForecastDaytimeTemperatureDisplayMode: ForecastDaytimeTemperatureDisplayMode {
        get {
            let rawValue = Self.defaults.string(forKey: Self.dailyForecastDaytimeTemperatureDisplayModeKey)
            return ForecastDaytimeTemperatureDisplayMode(rawValue: rawValue ?? "") ?? .replaceValues
        }
        set {
            objectWillChange.send()
            Self.defaults.set(newValue.rawValue, forKey: Self.dailyForecastDaytimeTemperatureDisplayModeKey)
            nc.post(name: Notification.Name("UnitChanged"), object: nil)
        }
    }

    var dailyForecastDaytimeTemperatureRangeMode: ForecastDaytimeTemperatureRangeMode {
        get {
            let rawValue = Self.defaults.string(forKey: Self.dailyForecastDaytimeTemperatureRangeModeKey)
            return ForecastDaytimeTemperatureRangeMode(rawValue: rawValue ?? "") ?? .sunriseSunset
        }
        set {
            objectWillChange.send()
            Self.defaults.set(newValue.rawValue, forKey: Self.dailyForecastDaytimeTemperatureRangeModeKey)
            nc.post(name: Notification.Name("UnitChanged"), object: nil)
        }
    }

    var dailyForecastDaytimeCustomStartHour: Int {
        guard Self.defaults.object(forKey: Self.dailyForecastDaytimeCustomStartHourKey) != nil else {
            return 9
        }

        return Self.clampedHour(Self.defaults.integer(forKey: Self.dailyForecastDaytimeCustomStartHourKey))
    }

    var dailyForecastDaytimeCustomEndHour: Int {
        guard Self.defaults.object(forKey: Self.dailyForecastDaytimeCustomEndHourKey) != nil else {
            return 18
        }

        return Self.clampedHour(Self.defaults.integer(forKey: Self.dailyForecastDaytimeCustomEndHourKey))
    }

    func updateDailyForecastDaytimeCustomStartHour(_ hour: Int) {
        let startHour = Self.clampedHour(hour)
        let endHour = max(startHour, dailyForecastDaytimeCustomEndHour)
        updateDailyForecastDaytimeCustomHours(startHour: startHour, endHour: endHour)
    }

    func updateDailyForecastDaytimeCustomEndHour(_ hour: Int) {
        let endHour = Self.clampedHour(hour)
        let startHour = min(dailyForecastDaytimeCustomStartHour, endHour)
        updateDailyForecastDaytimeCustomHours(startHour: startHour, endHour: endHour)
    }

    private func updateDailyForecastDaytimeCustomHours(startHour: Int, endHour: Int) {
        objectWillChange.send()
        Self.defaults.set(startHour, forKey: Self.dailyForecastDaytimeCustomStartHourKey)
        Self.defaults.set(endHour, forKey: Self.dailyForecastDaytimeCustomEndHourKey)
        nc.post(name: Notification.Name("UnitChanged"), object: nil)
    }

    static var resolvedTimeFormatAPIValue: String {
        resolvedTimeFormatPreference.resolvedAPIValue
    }

    static var resolvedTimeFormatPreference: TimeFormatPreference {
        let rawValue = defaults.string(forKey: timeFormatPreferenceKey)
        return TimeFormatPreference(rawValue: rawValue ?? "") ?? .system
    }

    private static func clampedHour(_ hour: Int) -> Int {
        min(max(hour, 0), 23)
    }

    static func formattedTime(
        _ date: Date,
        timeZone: TimeZone? = nil,
        showsMinutes: Bool = true
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        if let timeZone {
            formatter.timeZone = timeZone
        }

        switch resolvedTimeFormatPreference {
        case .system:
            formatter.dateStyle = .none
            formatter.timeStyle = showsMinutes ? .short : .none
            if !showsMinutes {
                formatter.dateFormat = DateFormatter.dateFormat(
                    fromTemplate: "j",
                    options: 0,
                    locale: .autoupdatingCurrent
                )
            }
        case .h24:
            formatter.dateFormat = showsMinutes ? "HH:mm" : "HH"
        case .h12:
            formatter.dateFormat = showsMinutes ? "h:mm a" : "h a"
        }

        return formatter.string(from: date)
    }

    static func formattedDateTime(_ date: Date, timeZone: TimeZone? = nil) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        if let timeZone {
            dateFormatter.timeZone = timeZone
        }

        return "\(dateFormatter.string(from: date)), \(formattedTime(date, timeZone: timeZone))"
    }
}
