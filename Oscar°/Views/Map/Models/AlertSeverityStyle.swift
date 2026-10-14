import SwiftUI

enum AlertSeverityStyle {
    static func color(rank: Int, source: String? = nil) -> Color {
        if source == "meteoalarm" {
            return switch rank {
            case 3: .orange
            case 4: .red
            default: .yellow
            }
        }
        return switch rank {
        case 2: .orange
        case 3: .red
        case 4: .purple
        default: .yellow
        }
    }

    static func label(rank: Int, source: String? = nil) -> LocalizedStringKey {
        if let source, source != "dwd" {
            return switch rank {
            case 1: "Minor"
            case 2: "Moderate"
            case 3: "Severe"
            case 4: "Extreme"
            default: "Alert"
            }
        }
        return switch rank {
        case 2: "Markante Wetterwarnung"
        case 3: "Unwetterwarnung"
        case 4: "Extreme Unwetterwarnung"
        default: "Wetterwarnung"
        }
    }

    static func sourceName(_ source: String?, senderName: String? = nil) -> String {
        switch source {
        case "nws": "NOAA / National Weather Service"
        case "cwa": "CWA / Central Weather Administration"
        case "ec": "Environment Canada"
        case "meteoalarm":
            senderName.map { "\($0) · EUMETNET Meteoalarm" } ?? "EUMETNET Meteoalarm"
        default: "Deutscher Wetterdienst"
        }
    }

    static func sourceLogo(_ source: String?) -> String? {
        switch source {
        case "nws": "logo-noaa"
        case "cwa", "ec": nil
        case "meteoalarm": "logo-eumetnet"
        default: "logo-dwd"
        }
    }
}
