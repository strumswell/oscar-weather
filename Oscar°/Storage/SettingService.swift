import CoreData
import SwiftUI
import OSLog
import WidgetKit

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

@MainActor
@Observable
public final class SettingService {
    static let shared = SettingService()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Oscar",
        category: "Storage"
    )
    var settings: Settings?
    var oscarRadarLayer: Bool {
        didSet {
            UserDefaults.standard.set(oscarRadarLayer, forKey: "oscarRadarLayer")
        }
    }
    var activeTileLayerRaw: String? {
        didSet {
            UserDefaults.standard.set(activeTileLayerRaw, forKey: "activeTileLayer")
        }
    }
    var oscarRadarRegionRaw: String {
        didSet {
            // Shared app group so the radar widget reads the same region.
            Self.defaults.set(oscarRadarRegionRaw, forKey: "oscarRadarRegion")
        }
    }
    /// When true (default), radar playback morphs between frames along the server's
    /// motion fields (RainViewer-style smooth motion). False = exact frames only —
    /// also forced by the system Reduce Motion setting at render time.
    var radarSmoothMotion: Bool {
        didSet {
            UserDefaults.standard.set(radarSmoothMotion, forKey: "radarSmoothMotion")
        }
    }
    /// When true (default), map layers render with RainViewer-style soft edges
    /// (bicubic data sampling + smooth palette gradients). False = crisp isobands.
    var radarSoftRendering: Bool {
        didSet {
            UserDefaults.standard.set(radarSoftRendering, forKey: "radarSoftRendering")
        }
    }
    /// When true (default), the paused radar view overlays motion arrows showing
    /// where precipitation is heading.
    var radarMotionArrows: Bool {
        didSet {
            UserDefaults.standard.set(radarMotionArrows, forKey: "radarMotionArrows")
        }
    }
    /// When true (default), model temperature/wind layers show sampled city value
    /// bubbles on the map.
    var mapValueBubbles: Bool {
        didSet {
            UserDefaults.standard.set(mapValueBubbles, forKey: "mapValueBubbles")
        }
    }
    var timeFormatPreference: TimeFormatPreference {
        didSet {
            Self.defaults.set(timeFormatPreference.rawValue, forKey: Self.timeFormatPreferenceKey)
            nc.post(name: .unitChanged, object: nil)
        }
    }
    var dailyForecastDaytimeTemperaturesEnabled: Bool {
        didSet {
            Self.defaults.set(
                dailyForecastDaytimeTemperaturesEnabled,
                forKey: Self.dailyForecastDaytimeTemperaturesEnabledKey
            )
        }
    }
    var dailyForecastDaytimeTemperatureDisplayMode: ForecastDaytimeTemperatureDisplayMode {
        didSet {
            Self.defaults.set(
                dailyForecastDaytimeTemperatureDisplayMode.rawValue,
                forKey: Self.dailyForecastDaytimeTemperatureDisplayModeKey
            )
        }
    }
    var dailyForecastDaytimeTemperatureRangeMode: ForecastDaytimeTemperatureRangeMode {
        didSet {
            Self.defaults.set(
                dailyForecastDaytimeTemperatureRangeMode.rawValue,
                forKey: Self.dailyForecastDaytimeTemperatureRangeModeKey
            )
        }
    }
    var dailyForecastDaytimeCustomStartHour: Int {
        didSet {
            Self.defaults.set(
                dailyForecastDaytimeCustomStartHour,
                forKey: Self.dailyForecastDaytimeCustomStartHourKey
            )
        }
    }
    var dailyForecastDaytimeCustomEndHour: Int {
        didSet {
            Self.defaults.set(
                dailyForecastDaytimeCustomEndHour,
                forKey: Self.dailyForecastDaytimeCustomEndHourKey
            )
        }
    }
    var forecastModelPreference: ForecastModelPreference {
        didSet {
            Self.defaults.set(forecastModelPreference.rawValue, forKey: Self.forecastModelPreferenceKey)
            nc.post(name: .unitChanged, object: nil)
        }
    }
    private let context: NSManagedObjectContext
    private let pc = PersistenceController.shared
    private let nc = NotificationCenter.default
    nonisolated private static let timeFormatPreferenceKey = "timeFormatPreference"
    private static let dailyForecastDaytimeTemperaturesEnabledKey = "dailyForecastDaytimeTemperaturesEnabled"
    private static let dailyForecastDaytimeTemperatureDisplayModeKey = "dailyForecastDaytimeTemperatureDisplayMode"
    private static let dailyForecastDaytimeTemperatureRangeModeKey = "dailyForecastDaytimeTemperatureRangeMode"
    private static let dailyForecastDaytimeCustomStartHourKey = "dailyForecastDaytimeCustomStartHour"
    private static let dailyForecastDaytimeCustomEndHourKey = "dailyForecastDaytimeCustomEndHour"
    nonisolated private static let forecastModelPreferenceKey = "forecastModelPreference"
    // Units live in Core Data but are mirrored into shared defaults so the widget process (whose
    // Core Data view is cached at launch) reads the current value. See resolvedTemperatureUnit.
    nonisolated private static let temperatureUnitKey = "temperatureUnit"
    nonisolated private static let windSpeedUnitKey = "windSpeedUnit"
    nonisolated private static let precipitationUnitKey = "precipitationUnit"
    nonisolated(unsafe) private static let defaults = UserDefaults(suiteName: "group.cloud.bolte.Oscar") ?? .standard
    nonisolated private static let formatterLock = NSLock()
    nonisolated(unsafe) private static var formatterCache: [String: DateFormatter] = [:]

    private init() {
        oscarRadarLayer = UserDefaults.standard.bool(forKey: "oscarRadarLayer")
        activeTileLayerRaw = UserDefaults.standard.string(forKey: "activeTileLayer")
        // Prefer the shared app group; migrate a value written to standard defaults by older
        // builds so the radar widget (which can only read the group) stays in sync.
        let resolvedRadarRegion = Self.defaults.string(forKey: "oscarRadarRegion")
            ?? UserDefaults.standard.string(forKey: "oscarRadarRegion")
            ?? "germany"
        oscarRadarRegionRaw = resolvedRadarRegion
        Self.defaults.set(resolvedRadarRegion, forKey: "oscarRadarRegion")
        radarSmoothMotion = (UserDefaults.standard.object(forKey: "radarSmoothMotion") as? Bool) ?? true
        radarSoftRendering = (UserDefaults.standard.object(forKey: "radarSoftRendering") as? Bool) ?? true
        radarMotionArrows = (UserDefaults.standard.object(forKey: "radarMotionArrows") as? Bool) ?? true
        mapValueBubbles = (UserDefaults.standard.object(forKey: "mapValueBubbles") as? Bool) ?? true
        timeFormatPreference = TimeFormatPreference(
            rawValue: Self.defaults.string(forKey: Self.timeFormatPreferenceKey) ?? ""
        ) ?? .system
        dailyForecastDaytimeTemperaturesEnabled = Self.defaults.bool(
            forKey: Self.dailyForecastDaytimeTemperaturesEnabledKey
        )
        dailyForecastDaytimeTemperatureDisplayMode = ForecastDaytimeTemperatureDisplayMode(
            rawValue: Self.defaults.string(
                forKey: Self.dailyForecastDaytimeTemperatureDisplayModeKey
            ) ?? ""
        ) ?? .replaceValues
        dailyForecastDaytimeTemperatureRangeMode = ForecastDaytimeTemperatureRangeMode(
            rawValue: Self.defaults.string(
                forKey: Self.dailyForecastDaytimeTemperatureRangeModeKey
            ) ?? ""
        ) ?? .sunriseSunset
        dailyForecastDaytimeCustomStartHour = Self.defaults.object(
            forKey: Self.dailyForecastDaytimeCustomStartHourKey
        ) == nil
            ? 9
            : Self.clampedHour(
                Self.defaults.integer(forKey: Self.dailyForecastDaytimeCustomStartHourKey)
            )
        dailyForecastDaytimeCustomEndHour = Self.defaults.object(
            forKey: Self.dailyForecastDaytimeCustomEndHourKey
        ) == nil
            ? 18
            : Self.clampedHour(
                Self.defaults.integer(forKey: Self.dailyForecastDaytimeCustomEndHourKey)
            )
        forecastModelPreference = ForecastModelPreference(
            rawValue: Self.defaults.string(forKey: Self.forecastModelPreferenceKey) ?? ""
        ) ?? .bestMatch
        self.context = pc.container.viewContext
        self.update()
    }
    
    func save() {
        do {
            try self.context.save()
            update()
        } catch {
            Self.logger.error("Settings save failed: \(error.localizedDescription, privacy: .public)")
            context.rollback()
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
                mirrorUnitsToSharedDefaults()
            }
        } catch {
            Self.logger.error("Settings fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }
    }
    func updateTemperatureUnit(_ unit: String) {
        settings?.temperatureUnit = unit
        save()
        nc.post(name: .unitChanged, object: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func updateWindSpeedUnit(_ unit: String) {
        settings?.windSpeedUnit = unit
        save()
        nc.post(name: .unitChanged, object: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func updatePrecipitationUnit(_ unit: String) {
        settings?.precipitationUnit = unit
        save()
        nc.post(name: .unitChanged, object: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Copies the Core Data unit settings into shared defaults. Called after every load/save so
    /// the widget process (which can't see another process's Core Data writes) reads the latest
    /// units when it builds a timeline.
    private func mirrorUnitsToSharedDefaults() {
        Self.defaults.set(settings?.temperatureUnit ?? "celsius", forKey: Self.temperatureUnitKey)
        Self.defaults.set(settings?.windSpeedUnit ?? "kmh", forKey: Self.windSpeedUnitKey)
        Self.defaults.set(settings?.precipitationUnit ?? "mm", forKey: Self.precipitationUnitKey)
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
        dailyForecastDaytimeCustomStartHour = startHour
        dailyForecastDaytimeCustomEndHour = endHour
    }

    nonisolated static var resolvedTimeFormatAPIValue: String {
        resolvedTimeFormatPreference.resolvedAPIValue
    }

    nonisolated static var resolvedTimeFormatPreference: TimeFormatPreference {
        let rawValue = defaults.string(forKey: timeFormatPreferenceKey)
        return TimeFormatPreference(rawValue: rawValue ?? "") ?? .system
    }

    /// Reads the selected forecast model from shared defaults. Safe to call from extensions.
    nonisolated static var resolvedForecastModelPreference: ForecastModelPreference {
        let rawValue = defaults.string(forKey: forecastModelPreferenceKey)
        return ForecastModelPreference(rawValue: rawValue ?? "") ?? .bestMatch
    }

    /// Selected units read from shared defaults. Safe to call from the widget process, which must
    /// not read units from the viewContext-bound `settings` (cached at process launch, blind to
    /// the app's writes).
    nonisolated static var resolvedTemperatureUnit: String {
        defaults.string(forKey: temperatureUnitKey) ?? "celsius"
    }

    nonisolated static var resolvedWindSpeedUnit: String {
        defaults.string(forKey: windSpeedUnitKey) ?? "kmh"
    }

    nonisolated static var resolvedPrecipitationUnit: String {
        defaults.string(forKey: precipitationUnitKey) ?? "mm"
    }

    private static func clampedHour(_ hour: Int) -> Int {
        min(max(hour, 0), 23)
    }

    nonisolated static func formattedTime(
        _ date: Date,
        timeZone: TimeZone? = nil,
        showsMinutes: Bool = true
    ) -> String {
        let mode = resolvedTimeFormatPreference
        let key = "time|\(mode.rawValue)|\(showsMinutes)|\(timeZone?.identifier ?? "local")"
        return format(date, key: key) {
            $0.locale = .autoupdatingCurrent
            $0.timeZone = timeZone
            switch mode {
            case .system:
                $0.dateStyle = .none
                $0.timeStyle = showsMinutes ? .short : .none
                if !showsMinutes {
                    $0.dateFormat = DateFormatter.dateFormat(
                        fromTemplate: "j",
                        options: 0,
                        locale: .autoupdatingCurrent
                    )
                }
            case .h24:
                $0.dateFormat = showsMinutes ? "HH:mm" : "HH"
            case .h12:
                $0.dateFormat = showsMinutes ? "h:mm a" : "h a"
            }
        }
    }

    nonisolated static func formattedDateTime(_ date: Date, timeZone: TimeZone? = nil) -> String {
        let key = "date|\(timeZone?.identifier ?? "local")"
        let dateString = format(date, key: key) {
            $0.locale = .autoupdatingCurrent
            $0.timeZone = timeZone
            $0.dateStyle = .short
            $0.timeStyle = .none
        }
        return "\(dateString), \(formattedTime(date, timeZone: timeZone))"
    }

    nonisolated static func formattedWeekday(_ date: Date, timeZone: TimeZone) -> String {
        format(date, key: "weekday|\(timeZone.identifier)") {
            $0.locale = .autoupdatingCurrent
            $0.timeZone = timeZone
            $0.dateFormat = "EEEE"
        }
    }

    nonisolated private static func format(
        _ date: Date,
        key: String,
        configure: (DateFormatter) -> Void
    ) -> String {
        formatterLock.withLock {
            let formatter: DateFormatter
            if let cached = formatterCache[key] {
                formatter = cached
            } else {
                formatter = DateFormatter()
                configure(formatter)
                formatterCache[key] = formatter
            }
            return formatter.string(from: date)
        }
    }
}
