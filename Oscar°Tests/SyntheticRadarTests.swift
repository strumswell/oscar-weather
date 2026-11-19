import Foundation
import Testing
@testable import Oscar_

struct SyntheticRadarTests {
    @Test
    func fastGridMatchesPerPixelSampling() {
        for minutes in [0.0, 45, 120] {
            let slow = SyntheticRadar.valueGrid(minutes: minutes) { lat, lon, t in
                let v = SyntheticRadar.intensity(lat: lat, lon: lon, minutes: t)
                return v >= 0.02 ? UInt8(1 + min(219, v * 219)) : 0
            }
            #expect(SyntheticRadar.radarGrid(minutes: minutes) == slow)
        }
    }

    @Test
    func liveActivityStateDecodesWithAndWithoutPrecipKind() throws {
        let base = #"{"phase":"raining","endIsOpen":false,"peakMmPerHour":2,"observedAt":0,"timeline":[]"#
        func decode(_ extra: String) throws -> RainRadarActivityAttributes.ContentState {
            try JSONDecoder().decode(RainRadarActivityAttributes.ContentState.self, from: Data((base + extra + "}").utf8))
        }
        #expect(try decode("").precipKind == nil)
        #expect(try decode(#","precipKind":"snow""#).precipKind == "snow")
        #expect(try decode(#","precipKind":"hail""#).precipKind == "hail")
    }

    @Test
    func snowGateUsesColdestGroundInView() {
        // 4×2 cells over 0…40°E: sea-level byte 100 (= 6 °C with scale 0.1, offset −4) everywhere,
        // one 1000 m cell (byte 50 × 20 m) at the north-east corner cools to 6 − 6.5 = −0.5 °C.
        let field = RadarGridPayload(indices: [UInt8](repeating: 100, count: 8), width: 4, height: 2)
        var ground = [UInt8](repeating: 0, count: 8)
        ground[3] = 50
        let relief = RadarGridPayload(indices: ground, width: 4, height: 2)
        let radar = OscarRadarBounds(north: 50, south: 40, west: 0, east: 40)
        func possible(_ view: OscarRadarBounds?, threshold: Double = 3.25, fields: [RadarGridPayload]? = nil) -> Bool {
            OscarRadarState.snowPossible(fields: fields ?? [field], relief: relief, view: view, radar: radar,
                                         fieldScale: 0.1, fieldOffset: -4, lapse: 0.0065 * 20, threshold: threshold)
        }
        #expect(possible(nil))
        #expect(possible(OscarRadarBounds(north: 49, south: 48, west: 31, east: 32)))
        #expect(!possible(OscarRadarBounds(north: 49, south: 41, west: 1, east: 25)))
        #expect(!possible(OscarRadarBounds(north: 60, south: 55, west: 0, east: 40)))
        #expect(!possible(OscarRadarBounds(north: 49, south: 41, west: 1, east: 25), threshold: 5.9))
        #expect(possible(OscarRadarBounds(north: 49, south: 41, west: 1, east: 25), threshold: 6.01))
        #expect(possible(OscarRadarBounds(north: 49, south: 41, west: 1, east: 25),
                         fields: [RadarGridPayload(indices: [0], width: 1, height: 1)]))
    }
}
