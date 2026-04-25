import SwiftUI

enum HourlyDetailSection: String, CaseIterable, Identifiable {
    case atmosphere
    case wind
    case ground

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .atmosphere:
            "Allgemein"
        case .wind:
            "Wind & Druck"
        case .ground:
            "Boden"
        }
    }
}
