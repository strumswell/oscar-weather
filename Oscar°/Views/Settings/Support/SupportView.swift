import StoreKit
import SwiftUI

/// Pay-what-you-want support page. An icon wall drifts behind a hero window
/// that feathers into the canvas; the products are StoreKit `ProductView`s in
/// a custom tile style, so loading, purchase and entitlement stay native.
struct SupportView: View {
    private let supporter = SupporterStore.shared
    @State private var appeared = false
    @State private var purchases = 0

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
        .onInAppPurchaseCompletion { _, result in
            guard case .success(.success(let verification)) = result,
                  case .verified(let transaction) = verification else { return }
            supporter.markSupporter(since: transaction.originalPurchaseDate)
            await transaction.finish()
            purchases += 1
        }
        .sensoryFeedback(.success, trigger: purchases)
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

    private var canvas: some View {
        VStack(alignment: .leading, spacing: 24) {
            SupportIntro(isSupporter: supporter.isSupporter)
                .onboardingEntrance(appeared, delay: 0.1)
            SupportProductTiles(title: "Einmal unterstützen", ids: SupporterStore.tipProductIDs, showsName: false, pulse: purchases)
                .onboardingEntrance(appeared, delay: 0.3)
            SupportProductTiles(title: "Regelmäßig unterstützen", ids: SupporterStore.subscriptionProductIDs, showsName: true, pulse: purchases)
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
