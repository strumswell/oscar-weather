import CoreLocation
import Foundation

/// One active warning in the map's tap sheet. Since the `/area` overlay went
/// dissolved (severity shapes without per-alert text), taps resolve through
/// `/weather-alerts/point` and this is built from `OscarPointAlert`; the
/// attribute-based init remains for servers still serving per-alert features.
struct WeatherAlertInfo: Identifiable {
    let id: String
    /// Ingesting agency: "dwd" (Germany) or "nws" (US); nil from servers that
    /// predate the field. Drives attribution and severity terminology.
    let source: String?
    /// Originating national service behind a Meteoalarm alert ("Météo-France").
    let senderName: String?
    let event: String
    let severityRank: Int
    let headline: String?
    let details: String?
    let instruction: String?
    let onset: Date?
    let expires: Date?

    init?(attributes: [String: Any]) {
        guard let id = attributes["id"] as? String,
              let event = attributes["event"] as? String, !event.isEmpty else { return nil }
        self.id = id
        self.event = event
        source = attributes["source"] as? String
        senderName = attributes["sender_name"] as? String
        severityRank = attributes["severity_rank"] as? Int ?? 1
        headline = attributes["headline"] as? String
        details = attributes["description"] as? String
        instruction = attributes["instruction"] as? String
        onset = Self.date(attributes["onset_at"])
        expires = Self.date(attributes["expires_at"])
    }

    init(pointAlert: OscarPointAlert) {
        id = pointAlert.alertId
        source = pointAlert.source
        senderName = pointAlert.senderName
        event = pointAlert.event
        severityRank = Self.rank(ofSeverity: pointAlert.severity)
        headline = pointAlert.headline
        details = pointAlert.description
        instruction = pointAlert.instruction
        onset = pointAlert.onsetAt
        expires = pointAlert.expiresAt
    }

    /// Mirrors the server's `severityRank` CAP mapping.
    private static func rank(ofSeverity severity: String) -> Int {
        switch severity.trimmingCharacters(in: .whitespaces).lowercased() {
        case "minor": 1
        case "moderate": 2
        case "severe": 3
        case "extreme": 4
        default: 1
        }
    }

    private static func date(_ value: Any?) -> Date? {
        if let date = value as? Date { return date }
        guard let string = value as? String else { return nil }
        return parseFrameDate(string)
    }
}

extension [WeatherAlertInfo] {
    /// Active warnings first (severity breaks ties), then upcoming by start.
    func sortedForDisplay(now: Date = Date()) -> [WeatherAlertInfo] {
        sorted {
            let l = Swift.max(0, $0.onset?.timeIntervalSince(now) ?? 0)
            let r = Swift.max(0, $1.onset?.timeIntervalSince(now) ?? 0)
            return l != r ? l < r : $0.severityRank > $1.severityRank
        }
    }
}
