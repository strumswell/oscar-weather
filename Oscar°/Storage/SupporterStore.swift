//
//  SupporterStore.swift
//  Oscar°
//
//  "Paid and not refunded" flag that unlocks cosmetics. StoreKit's transaction history
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

    func start() async {
        Task {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                if transaction.revocationDate == nil {
                    markSupporter(since: transaction.originalPurchaseDate)
                } else {
                    await refresh()
                }
                await transaction.finish()
            }
        }
        await refresh()
    }

    private func refresh() async {
        var sawValid = false
        var sawRevoked = false
        for await result in Transaction.all {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate == nil {
                sawValid = true
                markSupporter(since: transaction.originalPurchaseDate)
            } else {
                sawRevoked = true
            }
        }
        if sawRevoked && !sawValid { revokeSupporter() }
    }

    private func revokeSupporter() {
        isSupporter = false
        AppGroup.defaults.set(false, forKey: Self.key)
        UsageStatsStore.shared.record { $0.supporterSince = nil }
        UsageStatsStore.shared.flush()
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
