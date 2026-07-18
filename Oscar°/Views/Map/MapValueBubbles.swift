//
//  MapValueBubbles.swift
//  Oscar°
//
//  City value bubbles for the model temperature/wind layers: curated city list,
//  grid sampling, and unit formatting. The chip artwork lives in MapChip.
//

import UIKit

enum MapValueBubbles {
    static func windLabel(metersPerSecond: Double, unit: String) -> String {
        switch WindSpeedUnit(settingValue: unit) {
        case .kmh: return "\(Int((metersPerSecond * 3.6).rounded()))"
        case .ms:  return "\(Int(metersPerSecond.rounded()))"
        case .mph: return "\(Int((metersPerSecond * 2.23694).rounded()))"
        case .kn:  return "\(Int((metersPerSecond * 1.94384).rounded()))"
        case .bft: return "\(BeaufortScale.force(forKilometersPerHour: metersPerSecond * 3.6))"
        }
    }

    /// Nearest grid index at a coordinate (0 / outside → nil). UV via the
    /// mercator-aligned image bounds, like the render quad.
    static func sampleGridIndex(
        payload: RadarGridPayload, bounds: OscarRadarBounds, lat: Double, lon: Double
    ) -> UInt8? {
        guard payload.width > 1, payload.height > 1,
              lat < bounds.north, lat > bounds.south,
              bounds.east > bounds.west else { return nil }
        let x = (lon - bounds.west) / (bounds.east - bounds.west)
        guard x >= 0, x <= 1 else { return nil }
        let yNorth = WebMercator.projectedY(latitude: bounds.north)
        let ySouth = WebMercator.projectedY(latitude: bounds.south)
        let y = (yNorth - WebMercator.projectedY(latitude: lat)) / (yNorth - ySouth)
        guard y >= 0, y <= 1 else { return nil }
        let px = Int((x * Double(payload.width - 1)).rounded())
        let py = Int((y * Double(payload.height - 1)).rounded())
        let index = payload.indices[py * payload.width + px]
        return index > 0 ? index : nil
    }

    /// Curated city set: rank tiers gate visibility by zoom (0 = metropolis,
    /// shown first; 2 = only zoomed in). European density favors the ICON-D2
    /// wedge; the world set is for GFS.
    static let bubbleCities: [(lat: Double, lon: Double, rank: Int, name: String)] = [
        // DACH + central Europe (ICON-D2 wedge)
        (52.52, 13.41, 0, "Berlin"), (53.55, 10.00, 1, "Hamburg"),
        (48.14, 11.58, 0, "München"), (50.94, 6.96, 1, "Köln"),
        (50.11, 8.68, 1, "Frankfurt"), (48.78, 9.18, 1, "Stuttgart"),
        (51.34, 12.37, 2, "Leipzig"), (51.05, 13.74, 2, "Dresden"),
        (52.37, 9.73, 2, "Hannover"), (49.45, 11.08, 2, "Nürnberg"),
        (53.08, 8.81, 2, "Bremen"), (51.46, 7.01, 2, "Essen"),
        (48.21, 16.37, 0, "Wien"), (47.07, 15.44, 2, "Graz"),
        (47.80, 13.04, 2, "Salzburg"), (47.27, 11.40, 2, "Innsbruck"),
        (47.37, 8.54, 1, "Zürich"), (46.20, 6.14, 1, "Genève"),
        (47.56, 7.59, 2, "Basel"), (46.95, 7.44, 2, "Bern"),
        (45.46, 9.19, 1, "Milano"), (45.07, 7.69, 1, "Torino"),
        (45.44, 12.32, 2, "Venezia"), (44.41, 8.93, 2, "Genova"),
        (44.49, 11.34, 2, "Bologna"), (43.77, 11.25, 1, "Firenze"),
        (50.08, 14.44, 1, "Praha"), (49.20, 16.61, 2, "Brno"),
        (52.37, 4.90, 0, "Amsterdam"), (51.92, 4.48, 2, "Rotterdam"),
        (50.85, 4.35, 1, "Brussels"), (51.22, 4.40, 2, "Antwerpen"),
        (49.61, 6.13, 2, "Luxembourg"), (48.86, 2.35, 0, "Paris"),
        (45.76, 4.84, 1, "Lyon"), (48.57, 7.75, 2, "Strasbourg"),
        (50.63, 3.07, 2, "Lille"), (44.84, -0.58, 1, "Bordeaux"),
        (43.60, 1.44, 1, "Toulouse"), (43.30, 5.37, 1, "Marseille"),
        (43.70, 7.27, 2, "Nice"), (55.68, 12.57, 1, "København"),
        (56.16, 10.20, 2, "Aarhus"), (57.71, 11.97, 1, "Göteborg"),
        (55.60, 13.00, 2, "Malmö"), (50.06, 19.94, 1, "Kraków"),
        (51.11, 17.03, 2, "Wrocław"), (52.41, 16.93, 2, "Poznań"),
        (54.35, 18.65, 2, "Gdańsk"), (47.50, 19.04, 1, "Budapest"),
        (48.15, 17.11, 2, "Bratislava"), (46.06, 14.51, 2, "Ljubljana"),
        (45.81, 15.98, 1, "Zagreb"), (43.86, 18.41, 2, "Sarajevo"),
        (51.51, -0.13, 0, "London"), (52.48, -1.90, 2, "Birmingham"),
        (53.48, -2.24, 1, "Manchester"), (55.95, -3.19, 1, "Edinburgh"),
        // DACH densification (zoomed-in ICON-D2 use)
        (51.23, 6.78, 2, "Düsseldorf"), (51.51, 7.47, 2, "Dortmund"),
        (51.96, 7.63, 2, "Münster"), (54.32, 10.14, 2, "Kiel"),
        (54.09, 12.10, 2, "Rostock"), (52.13, 11.62, 2, "Magdeburg"),
        (50.98, 11.03, 2, "Erfurt"), (51.31, 9.49, 2, "Kassel"),
        (48.00, 7.85, 2, "Freiburg"), (49.01, 8.40, 2, "Karlsruhe"),
        (49.49, 8.47, 2, "Mannheim"), (49.24, 6.99, 2, "Saarbrücken"),
        (49.01, 12.10, 2, "Regensburg"), (49.79, 9.95, 2, "Würzburg"),
        (48.40, 9.99, 2, "Ulm"), (50.78, 6.08, 2, "Aachen"),
        (52.02, 8.53, 2, "Bielefeld"), (52.27, 10.52, 2, "Braunschweig"),
        (52.28, 8.05, 2, "Osnabrück"), (53.87, 10.69, 2, "Lübeck"),
        (50.83, 12.92, 2, "Chemnitz"), (48.31, 14.29, 2, "Linz"),
        (46.62, 14.31, 2, "Klagenfurt"), (47.50, 9.75, 2, "Bregenz"),
        (46.00, 8.95, 2, "Lugano"), (47.42, 9.37, 2, "St. Gallen"),
        (46.52, 6.63, 2, "Lausanne"), (46.85, 9.53, 2, "Chur"),
        // Wider Europe densification
        (52.09, 5.12, 2, "Utrecht"), (51.44, 5.47, 2, "Eindhoven"),
        (47.22, -1.55, 2, "Nantes"), (43.61, 3.88, 2, "Montpellier"),
        (45.19, 5.72, 2, "Grenoble"), (40.85, 14.27, 1, "Napoli"),
        (38.12, 13.36, 2, "Palermo"), (45.44, 10.99, 2, "Verona"),
        (39.47, -0.38, 2, "Valencia"), (37.39, -5.99, 1, "Sevilla"),
        (41.15, -8.61, 2, "Porto"), (43.26, -2.93, 2, "Bilbao"),
        (41.65, -0.88, 2, "Zaragoza"), (55.86, -4.25, 2, "Glasgow"),
        (51.45, -2.59, 2, "Bristol"), (54.98, -1.61, 2, "Newcastle"),
        (60.39, 5.32, 2, "Bergen"), (63.43, 10.40, 2, "Trondheim"),
        (69.65, 18.96, 2, "Tromsø"), (28.12, -15.43, 2, "Las Palmas"),
        (54.69, 25.28, 2, "Vilnius"), (56.95, 24.11, 1, "Riga"),
        (59.44, 24.75, 2, "Tallinn"), (53.90, 27.56, 1, "Minsk"),
        (49.84, 24.03, 2, "Lviv"), (46.48, 30.73, 2, "Odesa"),
        (42.70, 23.32, 1, "Sofia"), (40.64, 22.94, 2, "Thessaloniki"),
        // World (GFS)
        (40.71, -74.01, 0, "New York"), (34.05, -118.24, 0, "Los Angeles"),
        (41.88, -87.63, 1, "Chicago"), (29.76, -95.37, 1, "Houston"),
        (25.76, -80.19, 1, "Miami"), (39.74, -104.99, 2, "Denver"),
        (47.61, -122.33, 1, "Seattle"), (37.77, -122.42, 1, "San Francisco"),
        (43.65, -79.38, 1, "Toronto"), (49.28, -123.12, 2, "Vancouver"),
        (45.50, -73.57, 2, "Montreal"), (19.43, -99.13, 0, "Mexico City"),
        (4.71, -74.07, 2, "Bogotá"), (-12.05, -77.04, 1, "Lima"),
        (-33.45, -70.67, 1, "Santiago"), (-23.55, -46.63, 0, "São Paulo"),
        (-34.60, -58.38, 0, "Buenos Aires"), (-22.91, -43.17, 1, "Rio de Janeiro"),
        (64.15, -21.94, 2, "Reykjavík"), (53.35, -6.26, 1, "Dublin"),
        (38.72, -9.14, 1, "Lisboa"), (40.42, -3.70, 0, "Madrid"),
        (41.39, 2.17, 1, "Barcelona"), (41.90, 12.50, 0, "Roma"),
        (37.98, 23.73, 1, "Athens"), (41.01, 28.98, 0, "Istanbul"),
        (59.91, 10.75, 1, "Oslo"), (59.33, 18.07, 0, "Stockholm"),
        (60.17, 24.94, 1, "Helsinki"), (52.23, 21.01, 0, "Warszawa"),
        (50.45, 30.52, 1, "Kyiv"), (44.43, 26.10, 1, "București"),
        (44.79, 20.46, 2, "Beograd"), (55.76, 37.62, 0, "Moscow"),
        (30.04, 31.24, 0, "Cairo"), (6.52, 3.38, 1, "Lagos"),
        (-1.29, 36.82, 2, "Nairobi"), (-26.20, 28.05, 1, "Johannesburg"),
        (-33.92, 18.42, 2, "Cape Town"), (33.57, -7.59, 2, "Casablanca"),
        (36.75, 3.06, 2, "Algiers"), (36.81, 10.17, 2, "Tunis"),
        (32.08, 34.78, 2, "Tel Aviv"), (25.20, 55.27, 1, "Dubai"),
        (24.71, 46.68, 1, "Riyadh"), (35.69, 51.39, 1, "Tehran"),
        (24.86, 67.00, 1, "Karachi"), (19.08, 72.88, 0, "Mumbai"),
        (28.61, 77.21, 0, "New Delhi"), (23.81, 90.41, 2, "Dhaka"),
        (13.76, 100.50, 1, "Bangkok"), (1.35, 103.82, 0, "Singapore"),
        (-6.21, 106.85, 1, "Jakarta"), (22.32, 114.17, 1, "Hong Kong"),
        (31.23, 121.47, 0, "Shanghai"), (39.90, 116.41, 0, "Beijing"),
        (37.57, 126.98, 0, "Seoul"), (35.68, 139.69, 0, "Tokyo"),
        (25.03, 121.57, 2, "Taipei"), (14.60, 120.98, 2, "Manila"),
        (-33.87, 151.21, 0, "Sydney"), (-37.81, 144.96, 1, "Melbourne"),
        (-31.95, 115.86, 2, "Perth"), (-36.85, 174.76, 2, "Auckland"),
        (61.22, -149.90, 2, "Anchorage"), (21.31, -157.86, 2, "Honolulu"),
        // World densification
        (33.45, -112.07, 2, "Phoenix"), (32.78, -96.80, 1, "Dallas"),
        (33.75, -84.39, 1, "Atlanta"), (42.36, -71.06, 1, "Boston"),
        (39.95, -75.17, 2, "Philadelphia"), (38.91, -77.04, 1, "Washington"),
        (44.98, -93.27, 2, "Minneapolis"), (29.95, -90.07, 2, "New Orleans"),
        (40.76, -111.89, 2, "Salt Lake City"), (36.17, -115.14, 2, "Las Vegas"),
        (32.72, -117.16, 2, "San Diego"), (51.05, -114.07, 2, "Calgary"),
        (23.11, -82.37, 2, "Havana"), (8.98, -79.52, 2, "Panama City"),
        (10.49, -66.88, 2, "Caracas"), (-0.18, -78.47, 2, "Quito"),
        (-16.49, -68.15, 2, "La Paz"), (-15.79, -47.88, 2, "Brasília"),
        (-8.05, -34.88, 2, "Recife"), (-3.12, -60.02, 2, "Manaus"),
        (-34.90, -56.19, 2, "Montevideo"), (5.56, -0.20, 2, "Accra"),
        (14.72, -17.47, 2, "Dakar"), (9.01, 38.75, 2, "Addis Ababa"),
        (-6.79, 39.21, 2, "Dar es Salaam"), (15.59, 32.53, 2, "Khartoum"),
        (-4.32, 15.31, 2, "Kinshasa"), (-8.84, 13.23, 2, "Luanda"),
        (33.31, 44.37, 1, "Baghdad"), (25.29, 51.53, 2, "Doha"),
        (29.38, 47.99, 2, "Kuwait City"), (41.30, 69.24, 2, "Tashkent"),
        (43.24, 76.89, 2, "Almaty"), (56.84, 60.61, 2, "Yekaterinburg"),
        (55.03, 82.92, 2, "Novosibirsk"), (43.12, 131.89, 2, "Vladivostok"),
        (47.89, 106.91, 2, "Ulaanbaatar"), (30.57, 104.07, 1, "Chengdu"),
        (34.34, 108.94, 2, "Xi'an"), (23.13, 113.26, 1, "Guangzhou"),
        (30.59, 114.31, 2, "Wuhan"), (21.03, 105.85, 1, "Hanoi"),
        (10.82, 106.63, 1, "Ho Chi Minh City"), (11.56, 104.92, 2, "Phnom Penh"),
        (16.87, 96.20, 2, "Yangon"), (3.14, 101.69, 1, "Kuala Lumpur"),
        (6.93, 79.85, 2, "Colombo"), (13.08, 80.27, 1, "Chennai"),
        (22.57, 88.36, 1, "Kolkata"), (17.38, 78.49, 2, "Hyderabad"),
        (12.97, 77.59, 1, "Bengaluru"), (34.69, 135.50, 1, "Osaka"),
        (43.06, 141.35, 2, "Sapporo"), (33.59, 130.40, 2, "Fukuoka"),
        (35.18, 129.08, 2, "Busan"), (-27.47, 153.03, 1, "Brisbane"),
        (-34.93, 138.60, 2, "Adelaide"), (-12.46, 130.84, 2, "Darwin"),
    ]
}
