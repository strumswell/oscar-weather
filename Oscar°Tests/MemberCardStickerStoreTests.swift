import Foundation
import Testing
@testable import Oscar_

struct MemberCardStickerStoreTests {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "MemberCardStickerStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func placement(_ asset: String) -> MemberCardStickerPlacement {
        MemberCardStickerPlacement(assetName: asset, xRatio: 0.25, yRatio: 0.5, scale: 1.2, rotation: 0.3, zIndex: 1)
    }

    @Test
    func roundTripsThroughTheVersionedEnvelope() throws {
        let defaults = try makeDefaults()
        let store = MemberCardStickerStore(defaults: defaults)
        let placements = [placement("sticker_sun"), placement("sticker_oscar")]

        store.save(placements)

        #expect(store.load() == placements)
    }

    @Test
    func readsTheLegacyPlainArray() throws {
        let defaults = try makeDefaults()
        let placements = [placement("sticker_umbrella")]
        defaults.set(try JSONEncoder().encode(placements), forKey: "memberCardStickerPlacements")

        #expect(MemberCardStickerStore(defaults: defaults).load() == placements)
    }

    @Test
    func emptySaveClearsTheKey() throws {
        let defaults = try makeDefaults()
        let store = MemberCardStickerStore(defaults: defaults)
        store.save([placement("sticker_pest")])
        store.save([])

        #expect(defaults.data(forKey: "memberCardStickerPlacements") == nil)
        #expect(store.load().isEmpty)
    }

    @Test
    func undecodableDataFallsBackToNothing() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("nonsense".utf8), forKey: "memberCardStickerPlacements")

        #expect(MemberCardStickerStore(defaults: defaults).load().isEmpty)
    }
}
