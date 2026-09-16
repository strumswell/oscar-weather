import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import Oscar_

/// The local `Oscar°.storekit` config must list exactly the products the app asks for.
struct StoreKitConfigTests {
    @Test @MainActor
    func configOffersEveryProductTheAppUses() async throws {
        let configURL = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Oscar.storekit")
        let session = try SKTestSession(contentsOf: configURL)
        defer { withExtendedLifetime(session) {} }

        let ids = SupporterStore.tipProductIDs + SupporterStore.subscriptionProductIDs
        let products = try await Product.products(for: ids)

        #expect(Set(products.map(\.id)) == Set(ids))
        #expect(products.count(where: { $0.type == .consumable }) == 3)
        #expect(products.count(where: { $0.type == .autoRenewable }) == 2)
    }
}
