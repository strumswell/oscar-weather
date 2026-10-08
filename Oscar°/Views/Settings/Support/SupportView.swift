import StoreKit
import SwiftUI

/// Pay-what-you-want support page. An icon wall drifts behind a hero window
/// that feathers into the canvas; the products are StoreKit `ProductView`s in
/// a custom tile style, so loading, purchase and entitlement stay native.
struct SupportView: View {
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

    private static let productIDs = SupporterStore.tipProductIDs + SupporterStore.subscriptionProductIDs

    private static let heroFraction = 0.25
    private static let featherHeight = 90.0

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroWindow
                canvas
            }
        }
        .background(alignment: .top) {
            // Only the band above the canvas is ever visible.
            GeometryReader { proxy in
                IconWall()
                    .frame(height: proxy.size.height * 0.5, alignment: .top)
                    .clipped()
                    .modifier(ShineModifier())
            }
            .ignoresSafeArea()
        }
        // Over everything, tab bar and sheet included; the win fades itself
        // in and out, so the cover's own slide is switched off.
        .fullScreenCover(item: $thanks) { treat in
            SupportThanks(treat: treat, close: closeWin)
                .presentationBackground(.clear)
        }
        .onInAppPurchaseCompletion { product, result in
            guard case .success(.success(let verification)) = result,
                  case .verified(let transaction) = verification else { return }
            supporter.markSupporter(since: transaction.originalPurchaseDate)
            await transaction.finish()
            purchases += 1
            // Every reel rolls onto the bought treat, then the win takes the screen.
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
                    max(height * Self.heroFraction - Self.featherHeight, 0)
                }
            LinearGradient(
                colors: [Color(uiColor: .systemBackground).opacity(0), Color(uiColor: .systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.featherHeight)
        }
    }

    /// After the win the reels roll on to fresh treats, so no tile keeps
    /// showing the bought treat over another tier's price.
    private func closeWin() {
        withoutCoverAnimation { thanks = nil }
        roll()
    }

    private func withoutCoverAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    /// Every tile gets a different treat; the reels roll for about three seconds.
    private func roll() {
        for id in Self.productIDs {
            treats[id] = .pick(for: id, excluding: treats[id])
        }
        rolls += 1
        isRolling = true
        Task {
            // Reel clicks: steady while the reels run at full speed, then
            // slowing down with them, about 3 s in total.
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
            SupportIntro(isSupporter: supporter.isSupporter)
                .onboardingEntrance(appeared, delay: 0.1)
            SupportProductTiles(
                title: "Einmal unterstützen",
                ids: SupporterStore.tipProductIDs,
                treats: treats,
                jackpot: jackpot,
                shuffle: roll,
                isShuffling: isRolling
            )
                .onboardingEntrance(appeared, delay: 0.3)
            SupportProductTiles(title: "Regelmäßig unterstützen", ids: SupporterStore.subscriptionProductIDs, treats: treats, jackpot: jackpot)
                .onboardingEntrance(appeared, delay: 0.4)
            SupportFooter()
                .onboardingEntrance(appeared, delay: 0.5)
        }
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Reaches far below the content so the bottom bounce never reveals the wall.
        .background(Color(uiColor: .systemBackground).padding(.bottom, -1000))
    }
}

#Preview {
    NavigationStack {
        SupportView()
    }
}
