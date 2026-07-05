//
//  AppIconCatalog.swift
//  Oscar°
//
//  Created by Codex on 09.05.26.
//

import Foundation

struct AppIconOption: Identifiable, Equatable {
    let id: String
    let name: LocalizedStringResource
    let alternateIconName: String?
    let previewAssetName: String
}

struct AppIconSection: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let icons: [AppIconOption]
}

enum AppIconCatalog {
    static let sections: [AppIconSection] = [
        AppIconSection(
            id: "original",
            title: "Original",
            icons: [
                AppIconOption(
                    id: "original",
                    name: "Original",
                    alternateIconName: nil,
                    previewAssetName: "AppIconOriginalPreview"
                ),
                AppIconOption(id: "classic-halloween", name: "Halloween", alternateIconName: "AppIconClassicHalloween", previewAssetName: "AppIconClassicHalloweenPreview"),
                AppIconOption(id: "classic-jungle", name: "Dschungel", alternateIconName: "AppIconClassicJungle", previewAssetName: "AppIconClassicJunglePreview")
            ]
        ),
        AppIconSection(
            id: "chill",
            title: "Chill",
            icons: [
                AppIconOption(id: "chill-day", name: "Tag", alternateIconName: "AppIconChillDay", previewAssetName: "AppIconChillDayPreview"),
                AppIconOption(id: "chill-day-radar", name: "Radar", alternateIconName: "AppIconChillDayRadar", previewAssetName: "AppIconChillDayRadarPreview"),
                AppIconOption(id: "chill-night", name: "Nacht", alternateIconName: "AppIconChillNight", previewAssetName: "AppIconChillNightPreview")
            ]
        ),
        AppIconSection(
            id: "tv",
            title: "TV",
            icons: [
                AppIconOption(id: "tv-classic", name: "Original", alternateIconName: "AppIconTVClassic", previewAssetName: "AppIconTVClassicPreview"),
                AppIconOption(id: "tv-climate-change-oscar", name: "Klimakatastrophe", alternateIconName: "AppIconTVClimateChangeOscar", previewAssetName: "AppIconTVClimateChangeOscarPreview"),
                AppIconOption(id: "tv-rainy-oscar", name: "Regnerisch", alternateIconName: "AppIconTVRainyOscar", previewAssetName: "AppIconTVRainyOscarPreview"),
                AppIconOption(id: "tv-sunny-oscar", name: "Sonnig", alternateIconName: "AppIconTVSunnyOscar", previewAssetName: "AppIconTVSunnyOscarPreview")
            ]
        ),
        AppIconSection(
            id: "space",
            title: "Space",
            icons: [
                AppIconOption(id: "space-ship-oscar", name: "Weltraum", alternateIconName: "AppIconSpaceShipOscar", previewAssetName: "AppIconSpaceShipOscarPreview"),
                AppIconOption(id: "mecha-oscar", name: "Mecha", alternateIconName: "AppIconMechaOscar", previewAssetName: "AppIconMechaOscarPreview"),
                AppIconOption(id: "mecha-eu-oscar", name: "EU-Mecha", alternateIconName: "AppIconMechaEUOscar", previewAssetName: "AppIconMechaEUOscarPreview")
            ]
        ),
        AppIconSection(
            id: "flat-oscar",
            title: "Einfach",
            icons: [
                AppIconOption(id: "flat-oscar-classic", name: "Original", alternateIconName: "AppIconFlatOscarClassic", previewAssetName: "AppIconFlatOscarClassicPreview"),
                // AppIconOption(id: "flat-oscar-sun", name: "Original 2", alternateIconName: "AppIconFlatOscarSun", previewAssetName: "AppIconFlatOscarSunPreview"),
                AppIconOption(id: "flat-oscar-black", name: "Mono", alternateIconName: "AppIconFlatOscarBlack", previewAssetName: "AppIconFlatOscarBlackPreview"),
                AppIconOption(id: "flat-oscar-kawaii", name: "Kawaii", alternateIconName: "AppIconFlatOscarKawaii", previewAssetName: "AppIconFlatOscarKawaiiPreview"),
                AppIconOption(id: "flat-oscar-sky", name: "Himmel", alternateIconName: "AppIconFlatOscarSky", previewAssetName: "AppIconFlatOscarSkyPreview")
            ]
        )
    ]

    static var alternateIconNames: [String] {
        sections
            .flatMap(\.icons)
            .compactMap(\.alternateIconName)
    }
}
