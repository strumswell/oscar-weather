import StoreKit
import SwiftUI

struct SupportView: View {
    var close: (() -> Void)?

    private let supporter = SupporterStore.shared
    @State private var appeared = false
    @State private var purchases = 0
    @State private var treats = Self.freshTreats()
    @State private var rolls = 0
    @State private var isRolling = false
    @State private var ticks = 0
    @State private var jackpot: SupportJackpot?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thanks: SupportTreat?
    @State private var pendingProductID: String?

    private static let productIDs = SupporterStore.tipProductIDs + SupporterStore.subscriptionProductIDs

    private var heroFraction: Double { close == nil ? 0.25 : 0.17 }
    private static let featherHeight = 90.0

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroWindow
                canvas
            }
        }
        .background(alignment: .top) {
            GeometryReader { proxy in
                IconWall()
                    .frame(height: proxy.size.height * 0.5, alignment: .top)
                    .clipped()
                    .modifier(ShineModifier())
            }
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            if let close {
                Button(action: close) {
                    Text("Nicht jetzt")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .fullScreenCover(item: $thanks) { treat in
            SupportThanks(treat: treat, close: closeWin)
                .presentationBackground(.clear)
        }
        .onInAppPurchaseStart { product in
            pendingProductID = product.id
        }
        .onInAppPurchaseCompletion { product, result in
            pendingProductID = nil
            guard case .success(.success(let verification)) = result,
                  case .verified(let transaction) = verification else { return }
            supporter.markSupporter(since: transaction.originalPurchaseDate)
            await transaction.finish()
            purchases += 1
            guard let treat = treats[product.id] else { return }
            jackpot = SupportJackpot(id: (jackpot?.id ?? 0) + 1, treat: treat)
            if !reduceMotion { try? await Task.sleep(for: .seconds(3.6)) }
            withoutCoverAnimation { thanks = treat }
        }
        .sensoryFeedback(.success, trigger: purchases)
        .sensoryFeedback(.impact(weight: .light), trigger: rolls)
        .sensoryFeedback(.selection, trigger: ticks)
        .onAppear { appeared = true }
        .toolbarTitleDisplayMode(.inline)
    }

    private var heroWindow: some View {
        VStack(spacing: 0) {
            Color.clear
                .containerRelativeFrame(.vertical) { height, _ in
                    max(height * heroFraction - Self.featherHeight, 0)
                }
            LinearGradient(
                colors: [Color(uiColor: .systemBackground).opacity(0), Color(uiColor: .systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.featherHeight)
        }
    }

    private func closeWin() {
        if let close {
            close()
            return
        }
        withoutCoverAnimation { thanks = nil }
        roll()
    }

    private func withoutCoverAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    private func roll() {
        for id in Self.productIDs {
            treats[id] = .pick(for: id, excluding: treats[id])
        }
        rolls += 1
        isRolling = true
        Task {
            var gap = 0.05
            for step in 0..<50 where gap < 0.25 {
                try? await Task.sleep(for: .seconds(gap))
                ticks += 1
                if step >= 30 { gap *= 1.15 }
            }
            try? await Task.sleep(for: .seconds(0.6))
            isRolling = false
        }
    }

    private static func freshTreats() -> [String: SupportTreat] {
        Dictionary(uniqueKeysWithValues: productIDs.map { ($0, SupportTreat.pick(for: $0)) })
    }

    private var canvas: some View {
        VStack(alignment: .leading, spacing: 24) {
            SupportIntro(isSupporter: supporter.isSupporter, isAsking: close != nil)
                .onboardingEntrance(appeared, delay: 0.1)
            SupportProductTiles(
                title: "Einmal unterstützen",
                ids: SupporterStore.tipProductIDs,
                treats: treats,
                jackpot: jackpot,
                pendingID: pendingProductID,
                shuffle: roll,
                isShuffling: isRolling
            )
                .onboardingEntrance(appeared, delay: 0.3)
            SupportProductTiles(title: "Regelmäßig unterstützen", ids: SupporterStore.subscriptionProductIDs, treats: treats, jackpot: jackpot, pendingID: pendingProductID)
                .onboardingEntrance(appeared, delay: 0.4)
            SupportFooter()
                .onboardingEntrance(appeared, delay: 0.5)
        }
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .systemBackground).padding(.bottom, -1000))
    }
}

#Preview {
    NavigationStack {
        SupportView()
    }
}
