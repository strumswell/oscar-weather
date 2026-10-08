import Testing
import UIKit
@testable import Oscar_

@MainActor
struct SupportTreatTests {
    @Test
    func everyProductHasTreatsToRollBetween() {
        for id in SupporterStore.tipProductIDs + SupporterStore.subscriptionProductIDs {
            #expect((SupportTreat.catalog[id]?.count ?? 0) >= 2, "\(id)")
        }
    }

    @Test
    func rollingNeverLandsOnTheSameTreat() {
        let id = SupporterStore.subscriptionProductIDs[1]
        let current = SupportTreat.pick(for: id)
        for _ in 0..<50 {
            #expect(SupportTreat.pick(for: id, excluding: current) != current)
        }
    }

    @Test
    func everyTreatImageIsInTheAssetCatalog() {
        for image in SupportTreat.allImages {
            #expect(UIImage(named: image) != nil, "\(image)")
        }
    }
}
