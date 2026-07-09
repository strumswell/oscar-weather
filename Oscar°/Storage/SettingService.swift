import CoreData
import SwiftUI
import OSLog
import WidgetKit

enum MapBasemapStyle: String, CaseIterable, Identifiable {
    case fiord
    case dark
    case positron

    var id: String { rawValue }

    /// OpenFreeMap style endpoint (no API key).
    var styleURL: URL {
        URL(string: "https://tiles.openfreemap.org/styles/\(rawValue)")!
    }

    var label: LocalizedStringKey {
        switch self {
        case .fiord: return "Fiord"
        case .dark: return "Dunkel"
        case .positron: return "Hell"
        }
    }
}

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
    /// Units are mirrored out of Core Data into plain stored properties: mutating an
    /// @NSManaged field fires no @Observable change, so views bound to `settings` went
    /// stale. Views read/write these; the didSet persists back to Core Data.
    var temperatureUnit: String {
        didSet { unitDidChange() }
    }
    var windSpeedUnit: String {
        didSet { unitDidChange() }
    }
    var precipitationUnit: String {
        didSet { unitDidChange() }
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
    /// When true, the radar layer shows the TYPED product (rain/snow/hail coloring
    /// baked into the grid) where available — DWD and MRMS, not OPERA. The resolved
    /// product accessor lives in WeatherTileLayer.swift — `RadarProduct` isn't
    /// compiled into every target this file is.
    var radarPrecipTypeOverlay: Bool {
        didSet {
            UserDefaults.standard.set(radarPrecipTypeOverlay, forKey: "radarPrecipTypeOverlay")
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
    /// Opacity of the radar/model data overlays (0.3…1).
    var mapOverlayOpacity: Double {
        didSet {
            UserDefaults.standard.set(mapOverlayOpacity, forKey: "mapOverlayOpacity")
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
    private let context: NSManagedObjectContext
    private let pc = PersistenceController.shared
    private let nc = NotificationCenter.default
    /// True while `update()` copies Core Data values into the mirrored properties, so
    /// their didSet doesn't write straight back and re-post a refresh.
    private var isHydrating = false
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
        temperatureUnit = "celsius"
        windSpeedUnit = "kmh"
        precipitationUnit = "mm"
        oscarRadarLayer = UserDefaults.standard.bool(forKey: "oscarRadarLayer")
        activeTileLayerRaw = UserDefaults.standard.string(forKey: "activeTileLayer")
        // Prefer the shared app group; migrate a value written to standard defaults by older
        // builds so the radar widget (which can only read the group) stays in sync.
        let resolvedRadarRegion = Self.defaults.string(forKey: "oscarRadarRegion")
            ?? UserDefaults.standard.string(forKey: "oscarRadarRegion")
            ?? "germany"
        oscarRadarRegionRaw = resolvedRadarRegion
        Self.defaults.set(resolvedRadarRegion, forKey: "oscarRadarRegion")
        // Migration: the standalone "Niederschlagsart" layer (oscarRadarProduct ==
        // "precip_type") became a toggle on the radar layer.
        radarPrecipTypeOverlay = (UserDefaults.standard.object(forKey: "radarPrecipTypeOverlay") as? Bool)
            ?? (UserDefaults.standard.string(forKey: "oscarRadarProduct") == "precip_type")
        radarSmoothMotion = (UserDefaults.standard.object(forKey: "radarSmoothMotion") as? Bool) ?? true
        radarSoftRendering = (UserDefaults.standard.object(forKey: "radarSoftRendering") as? Bool) ?? true
        radarMotionArrows = (UserDefaults.standard.object(forKey: "radarMotionArrows") as? Bool) ?? true
        mapValueBubbles = (UserDefaults.standard.object(forKey: "mapValueBubbles") as? Bool) ?? true
        showAlertPolygons = UserDefaults.standard.bool(forKey: "showAlertPolygons")
        showStormCells = UserDefaults.standard.bool(forKey: "showStormCells")
        showIsobars = UserDefaults.standard.bool(forKey: "showIsobars")
        let storedOpacity = UserDefaults.standard.object(forKey: "mapOverlayOpacity") as? Double
        mapOverlayOpacity = min(max(storedOpacity ?? 0.7, 0.3), 1)
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
                isHydrating = true
                temperatureUnit = settings?.temperatureUnit ?? "celsius"
                windSpeedUnit = settings?.windSpeedUnit ?? "kmh"
                precipitationUnit = settings?.precipitationUnit ?? "mm"
                isHydrating = false
                mirrorUnitsToSharedDefaults()
            }
        } catch {
            Self.logger.error("Settings fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }
    }

    private func unitDidChange() {
        guard !isHydrating else { return }
        settings?.temperatureUnit = temperatureUnit
        settings?.windSpeedUnit = windSpeedUnit
        settings?.precipitationUnit = precipitationUnit
        save()
        nc.post(name: .weatherRefreshNeeded, object: nil)
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

    nonisolated static func formattedShortWeekday(_ date: Date, timeZone: TimeZone) -> String {
        format(date, key: "shortWeekday|\(timeZone.identifier)") {
            $0.locale = .autoupdatingCurrent
            $0.timeZone = timeZone
            $0.dateFormat = "EEE"
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
