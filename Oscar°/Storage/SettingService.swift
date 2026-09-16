import CoreData
import SwiftUI
import OSLog
import WidgetKit

@MainActor
@Observable
final class SettingService {
    static let shared = SettingService()
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Oscar",
        category: "Storage"
    )
    /// Units live in the shared app-group defaults so the widget process reads the
    /// same value the app just wrote. The watch has its own container and keeps
    /// its own copy.
    var temperatureUnit: String {
        didSet { unitDidChange(key: Self.temperatureUnitKey, value: temperatureUnit) }
    }
    var windSpeedUnit: String {
        didSet { unitDidChange(key: Self.windSpeedUnitKey, value: windSpeedUnit) }
    }
    var precipitationUnit: String {
        didSet { unitDidChange(key: Self.precipitationUnitKey, value: precipitationUnit) }
    }
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
    /// When true, active severe-weather warning areas render as a polygon overlay
    /// on top of whichever radar/model layer is showing.
    var showAlertPolygons: Bool {
        didSet {
            UserDefaults.standard.set(showAlertPolygons, forKey: "showAlertPolygons")
        }
    }
    /// When true, tracked precipitation cells render as markers with their
    /// extrapolated tracks, alongside whichever layer is showing.
    var showStormCells: Bool {
        didSet {
            UserDefaults.standard.set(showStormCells, forKey: "showStormCells")
        }
    }
    /// When true, MSLP isobars (with H/T centers) overlay the active model layer —
    /// the Großwetterlage view on top of pressure, temperature, or wind.
    var showIsobars: Bool {
        didSet {
            UserDefaults.standard.set(showIsobars, forKey: "showIsobars")
        }
    }
    /// When true, the satellite cloud layer is the SELECTED map layer with its own
    /// timeline (scrub through the cloud nowcast) — mutually exclusive with
    /// `oscarRadarLayer` and `activeTileLayer`, like those are with each other.
    var cloudLayerActive: Bool {
        didSet {
            UserDefaults.standard.set(cloudLayerActive, forKey: "cloudLayerActive")
        }
    }
    /// Opacity of the radar/model data overlays (0.3…1).
    var mapOverlayOpacity: Double {
        didSet {
            UserDefaults.standard.set(mapOverlayOpacity, forKey: "mapOverlayOpacity")
        }
    }
    /// Which reading the hourly detail sheet opens in: the chapters timeline
    /// (true) or the all-values deck.
    var hourlyDetailShowsChapters: Bool {
        didSet {
            UserDefaults.standard.set(hourlyDetailShowsChapters, forKey: "hourlyDetailShowsChapters")
        }
    }
    var mapBasemapStyleRaw: String {
        didSet {
            // Shared app group so the widget basemap prerender follows the map style.
            Self.defaults.set(mapBasemapStyleRaw, forKey: "mapBasemapStyle")
        }
    }
    var mapBasemapStyle: MapBasemapStyle {
        get { MapBasemapStyle(rawValue: mapBasemapStyleRaw) ?? .fiord }
        set { mapBasemapStyleRaw = newValue.rawValue }
    }
    var timeFormatPreference: TimeFormatPreference {
        didSet {
            Self.defaults.set(timeFormatPreference.rawValue, forKey: Self.timeFormatPreferenceKey)
            nc.post(name: .weatherRefreshNeeded, object: nil)
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
            let clamped = Self.clampedHour(dailyForecastDaytimeCustomStartHour)
            if clamped != dailyForecastDaytimeCustomStartHour {
                dailyForecastDaytimeCustomStartHour = clamped
                return
            }
            if dailyForecastDaytimeCustomEndHour < clamped {
                dailyForecastDaytimeCustomEndHour = clamped
            }
            Self.defaults.set(clamped, forKey: Self.dailyForecastDaytimeCustomStartHourKey)
        }
    }
    var dailyForecastDaytimeCustomEndHour: Int {
        didSet {
            let clamped = Self.clampedHour(dailyForecastDaytimeCustomEndHour)
            if clamped != dailyForecastDaytimeCustomEndHour {
                dailyForecastDaytimeCustomEndHour = clamped
                return
            }
            if dailyForecastDaytimeCustomStartHour > clamped {
                dailyForecastDaytimeCustomStartHour = clamped
            }
            Self.defaults.set(clamped, forKey: Self.dailyForecastDaytimeCustomEndHourKey)
        }
    }
    var forecastModelPreference: ForecastModelPreference {
        didSet {
            Self.defaults.set(forecastModelPreference.rawValue, forKey: Self.forecastModelPreferenceKey)
            nc.post(name: .weatherRefreshNeeded, object: nil)
        }
    }
    private let nc = NotificationCenter.default
    nonisolated private static let timeFormatPreferenceKey = "timeFormatPreference"
    private static let dailyForecastDaytimeTemperaturesEnabledKey = "dailyForecastDaytimeTemperaturesEnabled"
    private static let dailyForecastDaytimeTemperatureDisplayModeKey = "dailyForecastDaytimeTemperatureDisplayMode"
    private static let dailyForecastDaytimeTemperatureRangeModeKey = "dailyForecastDaytimeTemperatureRangeMode"
    private static let dailyForecastDaytimeCustomStartHourKey = "dailyForecastDaytimeCustomStartHour"
    private static let dailyForecastDaytimeCustomEndHourKey = "dailyForecastDaytimeCustomEndHour"
    nonisolated private static let forecastModelPreferenceKey = "forecastModelPreference"
    nonisolated private static let temperatureUnitKey = "temperatureUnit"
    nonisolated private static let windSpeedUnitKey = "windSpeedUnit"
    nonisolated private static let precipitationUnitKey = "precipitationUnit"
    nonisolated private static var defaults: UserDefaults { AppGroup.defaults }

    private init() {
        Self.migrateUnitsFromCoreDataIfNeeded()
        temperatureUnit = Self.resolvedTemperatureUnit
        windSpeedUnit = Self.resolvedWindSpeedUnit
        precipitationUnit = Self.resolvedPrecipitationUnit
        oscarRadarLayer = UserDefaults.standard.bool(forKey: "oscarRadarLayer")
        activeTileLayerRaw = UserDefaults.standard.string(forKey: "activeTileLayer")
        // Prefer the shared app group; migrate a value written to standard defaults by older
        // builds so the radar widget (which can only read the group) stays in sync.
        let resolvedRadarRegion = Self.defaults.string(forKey: "oscarRadarRegion")
            ?? UserDefaults.standard.string(forKey: "oscarRadarRegion")
            ?? "germany"
        oscarRadarRegionRaw = resolvedRadarRegion
        Self.defaults.set(resolvedRadarRegion, forKey: "oscarRadarRegion")
        UserDefaults.standard.removeObject(forKey: "radarPrecipTypeOverlay")
        UserDefaults.standard.removeObject(forKey: "oscarRadarProduct")
        radarSmoothMotion = (UserDefaults.standard.object(forKey: "radarSmoothMotion") as? Bool) ?? true
        radarSoftRendering = (UserDefaults.standard.object(forKey: "radarSoftRendering") as? Bool) ?? true
        radarMotionArrows = (UserDefaults.standard.object(forKey: "radarMotionArrows") as? Bool) ?? true
        mapValueBubbles = (UserDefaults.standard.object(forKey: "mapValueBubbles") as? Bool) ?? true
        showAlertPolygons = UserDefaults.standard.bool(forKey: "showAlertPolygons")
        showStormCells = UserDefaults.standard.bool(forKey: "showStormCells")
        showIsobars = UserDefaults.standard.bool(forKey: "showIsobars")
        cloudLayerActive = UserDefaults.standard.bool(forKey: "cloudLayerActive")
        let storedOpacity = UserDefaults.standard.object(forKey: "mapOverlayOpacity") as? Double
        mapOverlayOpacity = min(max(storedOpacity ?? 0.7, 0.3), 1)
        hourlyDetailShowsChapters = UserDefaults.standard.bool(forKey: "hourlyDetailShowsChapters")
        mapBasemapStyleRaw = Self.defaults.string(forKey: "mapBasemapStyle") ?? MapBasemapStyle.fiord.rawValue
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
    }

    private func unitDidChange(key: String, value: String) {
        Self.defaults.set(value, forKey: key)
        nc.post(name: .weatherRefreshNeeded, object: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Units used to live in the Core Data `Settings` row; installs that predate the
    /// app-group defaults copy them over once.
    private static func migrateUnitsFromCoreDataIfNeeded() {
        guard defaults.string(forKey: temperatureUnitKey) == nil else { return }
        let context = PersistenceController.shared.container.viewContext
        guard let stored = try? context.fetch(Settings.fetchRequest()).first else { return }
        defaults.set(stored.temperatureUnit ?? "celsius", forKey: temperatureUnitKey)
        defaults.set(stored.windSpeedUnit ?? "kmh", forKey: windSpeedUnitKey)
        defaults.set(stored.precipitationUnit ?? "mm", forKey: precipitationUnitKey)
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

}
