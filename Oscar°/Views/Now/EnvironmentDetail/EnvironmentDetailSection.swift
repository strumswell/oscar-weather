import SwiftUI

enum EnvironmentDetailSection: String, CaseIterable, Hashable, Identifiable {
    case aqi
    case uv
    case pollen

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .aqi:
            "Luftqualität"
        case .uv:
            "UV-Index"
        case .pollen:
            "Pollen"
        }
    }
}
