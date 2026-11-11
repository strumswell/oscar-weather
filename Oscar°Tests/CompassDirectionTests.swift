import Foundation
import Testing
@testable import Oscar_

struct CompassDirectionTests {
    private let north = String(localized: "N_compass")
    private let northEast = String(localized: "NE_compass")
    private let northWest = String(localized: "NW_compass")

    @Test
    func sectorsAreDistinct() {
        let sectors = Set([0.0, 45, 90, 135, 180, 225, 270, 315].map(compassDirection))
        #expect(sectors.count == 8)
    }

    @Test
    func firstBoundaryBelongsToTheNextSector() {
        #expect(compassDirection(0) == north)
        #expect(compassDirection(22.4) == north)
        #expect(compassDirection(22.5) == northEast)
    }

    @Test
    func lastBoundaryBeforeNorthWrapsToNorth() {
        #expect(compassDirection(337.4) == northWest)
        #expect(compassDirection(337.5) == north)
        #expect(compassDirection(360) == north)
    }

    @Test(arguments: [-10.0, -90, -200, 450, 720])
    func outOfRangeInputClampsToNorth(degrees: Double) {
        #expect(compassDirection(degrees) == north)
    }
}
