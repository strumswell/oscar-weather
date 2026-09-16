import SwiftUI

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
