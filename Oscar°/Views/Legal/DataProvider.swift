import SwiftUI

struct DataProviderLink: Identifiable {
    let title: String
    let url: URL
    var id: String { url.absoluteString }
}

/// One credited data provider: the settings row and its attribution page.
struct DataProvider: Identifiable {
    let id: String
    let name: String
    /// Proper nouns stay verbatim; the rest resolves through the string catalog.
    var nameIsLocalized = false
    let title: String
    var titleIsLocalized = false
    let systemImage: String
    let tint: Color
    let about: String
    var license: String? = nil
    let links: [DataProviderLink]
    var sources: [DataProviderLink] = []

    var nameText: Text { nameIsLocalized ? Text(LocalizedStringKey(name)) : Text(verbatim: name) }
    var titleText: Text { titleIsLocalized ? Text(LocalizedStringKey(title)) : Text(verbatim: title) }
}

extension DataProvider {
    static let all: [DataProvider] = [
        DataProvider(
            id: "open-meteo", name: "Open-Meteo", nameIsLocalized: true,
            title: "Open-Meteo", titleIsLocalized: true,
            systemImage: "sun.max.fill", tint: .orange,
            about: "Open-Meteo ist eine Open-Source-Wetter-API, die offene Wetterdaten von verschiedenen internationalen Wetterdiensten sammelt. Oscar nutzt als nicht-kommerzielle App den kostenlosen Zugang zu Open-Meteo, unterstützt das Projekt aber mit einer monatlichen Spende von fünf Euro.",
            license: "Attribution 4.0 International (CC BY 4.0)",
            links: [DataProviderLink(title: "open-meteo.com", url: URL(string: "https://open-meteo.com/")!)],
            sources: [
                DataProviderLink(title: "ICON - Deutscher Wetterdienst (DWD)", url: URL(string: "https://www.dwd.de/")!),
                DataProviderLink(title: "GFS & HRRR - NOAA", url: URL(string: "https://www.noaa.gov/")!),
                DataProviderLink(title: "ARPEGE & AROME - Météo-France", url: URL(string: "https://meteofrance.com/")!),
                DataProviderLink(title: "IFS & AIFS - ECMWF", url: URL(string: "https://www.ecmwf.int/")!),
                DataProviderLink(title: "MSM & GSM - JMA", url: URL(string: "https://www.jma.go.jp/")!),
                DataProviderLink(title: "MET Nordic - MET Norway", url: URL(string: "https://www.met.no/")!),
                DataProviderLink(title: "HARMONIE - KNMI", url: URL(string: "https://www.knmi.nl/")!),
                DataProviderLink(title: "HARMONIE - DMI", url: URL(string: "https://www.dmi.dk/")!),
                DataProviderLink(title: "GEM - Canadian Weather Service", url: URL(string: "https://weather.gc.ca/")!),
                DataProviderLink(title: "GFS GRAPES - China Meteorological Administration (CMA)", url: URL(string: "https://www.cma.gov.cn/en/")!),
                DataProviderLink(title: "ACCESS-G - Australian Bureau of Meteorology (BOM)", url: URL(string: "http://www.bom.gov.au/")!),
                DataProviderLink(title: "COSMO 2I & 5M - AM ARPAE ARPAP", url: URL(string: "https://www.arpae.it/it")!),
            ]
        ),
        DataProvider(
            id: "dwd", name: "Deutscher Wetterdienst (DWD)", nameIsLocalized: true,
            title: "DWD", titleIsLocalized: true,
            systemImage: "cloud.rain.fill", tint: .blue,
            about: "Oscar verwendet Wetter- und Geodaten des Deutschen Wetterdienstes (DWD), unter anderem Radardaten, Prognosedaten aus dem ICON-Modell sowie amtliche Warnmeldungen. Datenbasis: Deutscher Wetterdienst. Die Daten werden unter den Open-Data-Nutzungsbedingungen des DWD bereitgestellt.",
            links: [
                DataProviderLink(title: "dwd.de", url: URL(string: "https://www.dwd.de/")!),
                DataProviderLink(title: "DWD Open Data", url: URL(string: "https://opendata.dwd.de/")!),
            ]
        ),
        DataProvider(
            id: "eumetnet", name: "EUMETNET (OPERA & Meteoalarm)", title: "EUMETNET",
            systemImage: "globe.europe.africa.fill", tint: .green,
            about: "Oscar verwendet das europäische Radarkomposit des OPERA-Programms von EUMETNET, dem Zusammenschluss der europäischen Wetterdienste, für das Regenradar in Europa außerhalb Zentraleuropas sowie amtliche Warnmeldungen der europäischen Warnplattform Meteoalarm. Die Nutzung stellt keine Unterstützung oder offizielle Verbindung zu EUMETNET dar.",
            links: [
                DataProviderLink(title: "eumetnet.eu", url: URL(string: "https://www.eumetnet.eu/")!),
                DataProviderLink(title: "OPERA-Programm", url: URL(string: "https://www.eumetnet.eu/activities/observations-programme/current-activities/opera/")!),
                DataProviderLink(title: "meteoalarm.org", url: URL(string: "https://meteoalarm.org/")!),
            ]
        ),
        DataProvider(
            id: "noaa", name: "NOAA & NWS", title: "NOAA",
            systemImage: "globe.americas.fill", tint: .indigo,
            about: "Oscar verwendet Daten der US-Wetterbehörde NOAA: Prognosedaten aus den Modellen GFS und HRRR, das MRMS-Radarkomposit für das Regenradar über den USA sowie amtliche Warnungen des National Weather Service (NWS). NOAA/NWS-Daten sind in der Regel gemeinfrei, sofern nicht anders gekennzeichnet. Die Nutzung stellt keine Unterstützung, Empfehlung oder offizielle Verbindung zu NOAA oder NWS dar.",
            links: [
                DataProviderLink(title: "noaa.gov", url: URL(string: "https://www.noaa.gov/")!),
                DataProviderLink(title: "GFS bei NOAA/NCEI", url: URL(string: "https://www.ncei.noaa.gov/products/weather-climate-models/global-forecast")!),
                DataProviderLink(title: "NWS Disclaimer", url: URL(string: "https://www.weather.gov/disclaimer/")!),
            ]
        ),
        DataProvider(
            id: "cwa", name: "Central Weather Administration (CWA)", title: "CWA",
            systemImage: "globe.asia.australia.fill", tint: .mint,
            about: "Oscar verwendet Daten der Central Weather Administration (CWA), der Wetterbehörde Taiwans: das QPESUMS-Radarkomposit für das Regenradar über Taiwan sowie amtliche Warnungen auf Landkreisebene. Die Nutzung stellt keine Unterstützung oder offizielle Verbindung zur CWA dar.",
            links: [DataProviderLink(title: "cwa.gov.tw", url: URL(string: "https://www.cwa.gov.tw/")!)]
        ),
        DataProvider(
            id: "redemet", name: "REDEMET (DECEA)", title: "REDEMET",
            systemImage: "globe.americas.fill", tint: .green,
            about: "Oscar verwendet Radardaten des brasilianischen Flugwetterdienstes REDEMET (DECEA) für das Regenradar über Brasilien. Die Nutzung stellt keine Unterstützung oder offizielle Verbindung zu REDEMET oder DECEA dar.",
            links: [DataProviderLink(title: "redemet.decea.mil.br", url: URL(string: "https://redemet.decea.mil.br/")!)]
        ),
        DataProvider(
            id: "aemet", name: "AEMET", title: "AEMET",
            systemImage: "globe.europe.africa.fill", tint: .purple,
            about: "Oscar verwendet Radardaten der Agencia Estatal de Meteorología (AEMET), des staatlichen spanischen Wetterdienstes, für das Regenradar über den Kanarischen Inseln. Die Nutzung stellt keine Unterstützung oder offizielle Verbindung zu AEMET dar.",
            links: [DataProviderLink(title: "aemet.es", url: URL(string: "https://www.aemet.es/")!)]
        ),
        DataProvider(
            id: "eccc", name: "Environment and Climate Change Canada", title: "ECCC",
            systemImage: "snowflake", tint: .cyan,
            about: "Oscar verwendet amtliche Wetterwarnungen von Environment and Climate Change Canada (ECCC) für Kanada. Die Nutzung stellt keine Unterstützung oder offizielle Verbindung zu ECCC dar.",
            links: [DataProviderLink(title: "weather.gc.ca", url: URL(string: "https://weather.gc.ca/")!)]
        ),
    ]
}
