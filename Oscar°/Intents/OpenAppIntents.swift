// Intents that bring the app to the front on the radar or the forecast.
import AppIntents
import Foundation

struct OpenRadarIntent: AppIntent {
    static let title: LocalizedStringResource = "Regenradar öffnen"
    static let description = IntentDescription("Öffnet die Karten mit dem Regenradar.")
    static let supportedModes: IntentModes = .foreground

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(.oscarRadar(nil)))
    }
}

struct OpenWeatherIntent: AppIntent {
    static let title: LocalizedStringResource = "Wetter öffnen"
    static let description = IntentDescription("Öffnet die Vorhersage für deinen Ort.")
    static let supportedModes: IntentModes = .foreground
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(.oscarPlace(nil)))
    }
}
