import SwiftUI

enum HourlyDetailSection: String, CaseIterable, Identifiable {
    case meteogram
    case atmosphere
    case wind
    case ground

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .meteogram:
            "Meteogramm"
        case .atmosphere:
            "Allgemein"
        case .wind:
            "Wind & Druck"
        case .ground:
            "Boden"
        }
    }
}
