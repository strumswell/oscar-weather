import SwiftUI

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
