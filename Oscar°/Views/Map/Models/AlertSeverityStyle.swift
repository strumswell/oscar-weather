import SwiftUI

enum AlertSeverityStyle {
    /// DWD ranks: 1 Minor, 2 Moderate, 3 Severe, 4 Extreme — same colors as the
    /// map polygons (`syncAlertPolygons`).
    static func color(rank: Int, source: String? = nil) -> Color {
        // Meteoalarm's ladder has no Minor: yellow IS Moderate ("vigilance jaune",
        // "allerta gialla"), so the generic scale would overstate every level by
        // one color against what national services show for the same warning.
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
        // Only DWD (or nil, from old DWD-only servers) uses the German
        // warning-level names; every other agency gets the CAP terms.
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

    /// Meteoalarm only aggregates the national services — when the server names
    /// the originating one, attribution shows both.
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

    /// Provider mark next to the source line; CWA and EC have no bundled logo.
    static func sourceLogo(_ source: String?) -> String? {
        switch source {
        case "nws": "logo-noaa"
        case "cwa", "ec": nil
        case "meteoalarm": "logo-eumetnet"
        default: "logo-dwd"
        }
    }
}
