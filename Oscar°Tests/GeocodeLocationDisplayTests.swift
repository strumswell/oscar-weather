import Testing
@testable import Oscar_

struct GeocodeLocationDisplayTests {
    @Test
    func detailLineSkipsTheNameAndEmptyParts() {
        var location = Components.Schemas.Location()
        location.name = "Leipzig"
        location.admin3 = "Leipzig"
        location.admin1 = "Sachsen"
        location.country = "Deutschland"

        #expect(location.detailLine == "Sachsen, Deutschland")
        #expect(location.displayName == "Leipzig")
    }

    @Test
    func detailLineIsNilWithoutRegionData() {
        var location = Components.Schemas.Location()
        location.name = "Nowhere"

        #expect(location.detailLine == nil)
    }

    @Test
    func flagEmojiComesFromTheCountryCode() {
        var location = Components.Schemas.Location()
        location.country_code = "de"
        #expect(location.flagEmoji == "🇩🇪")

        location.country_code = "TR"
        #expect(location.flagEmoji == "🇹🇷")

        location.country_code = "XYZ"
        #expect(location.flagEmoji == nil)
    }
}
