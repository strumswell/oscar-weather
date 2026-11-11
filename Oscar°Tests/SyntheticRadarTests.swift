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
}
