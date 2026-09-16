//
//  SupporterStore.swift
//  Oscar°
//
//  "Has ever paid" flag that unlocks cosmetics. StoreKit's transaction history
//  is the cross-device source of truth (per Apple ID); the flag is cached
//  locally so cosmetics unlock offline and before the first history fetch.
//

import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class SupporterStore {
    static let shared = SupporterStore()

    static let tipProductIDs = [
        "cloud.bolte.Oscar.tip.small",
        "cloud.bolte.Oscar.tip.medium",
        "cloud.bolte.Oscar.tip.large",
    ]
    static let subscriptionProductIDs = [
        "cloud.bolte.Oscar.supporter.monthly",
        "cloud.bolte.Oscar.supporter.yearly",
    ]

    private static let key = "supporter"

    private(set) var isSupporter = AppGroup.defaults.bool(forKey: SupporterStore.key)

    private init() {}

    /// Any verified purchase ever made on this Apple ID counts. Refunds and
    /// lapsed subscriptions keep the flag on purpose. Finished consumables
    /// appear in the history because of `SKIncludeConsumableInAppPurchaseHistory`.
    func start() async {
        Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                markSupporter(since: transaction.originalPurchaseDate)
                await transaction.finish()
            }
        }
        for await result in Transaction.all {
            guard case .verified(let transaction) = result else { continue }
            markSupporter(since: transaction.originalPurchaseDate)
        }
    }

    func markSupporter(since: Date) {
        if !isSupporter {
            isSupporter = true
            AppGroup.defaults.set(true, forKey: Self.key)
        }
        UsageStatsStore.shared.record {
            $0.supporterSince = min($0.supporterSince ?? since, since)
        }
    }
}
