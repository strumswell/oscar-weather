import SwiftUI

struct MemberCard: View {
    static let maxCardWidth: CGFloat = 460
    static let seenTierKey = "memberCardSeenTier"
    static let seenYearsKey = "memberCardSeenYears"
    static let signatureKey = "memberCardSignature"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var placements: [MemberCardStickerPlacement] = []
    @State private var cardWidth: CGFloat = 340
    @State private var status: MemberStatus
    @State private var backStats: [MemberCardBackStat]
    @State private var show: MemberCardShow
    @Binding var editorTab: MemberCardEditor.Tab?
    @Binding var style: MemberTier
    @State private var showsLab = UserDefaults.standard.bool(forKey: "memberCardLab")
    @AppStorage(MemberCard.signatureKey) private var signatureData = Data()

    init(editorTab: Binding<MemberCardEditor.Tab?>, style: Binding<MemberTier>) {
        _editorTab = editorTab
        _style = style
        let status = MemberStatus.current()
        _status = State(initialValue: status)
        _backStats = State(initialValue: MemberCardBackStat.all(for: status))
        let show = MemberCardShow()
        show.stampHidden = Self.hasUnseenStamp(status)
        show.revealFrom = Self.unseenTierUp(status)
        _show = State(initialValue: show)
    }

    var body: some View {
        MemberCardStage(show: show, tier: status.style, width: cardWidth, tiltActive: editorTab == nil) { style in
            surface(style: style)
        } back: {
            MemberCardBack(
                tier: status.style,
                stats: backStats,
                signature: MemberCardSignature.decode(signatureData),
                width: cardWidth,
                motion: show.motion,
                onSignatureTap: { openEditor(.signature) }
            )
        }
        .frame(width: cardWidth, height: cardWidth / MemberCardPalette.aspect)
        .contentShape(.rect)
        .onTapGesture { show.flip(reduceMotion: reduceMotion) }
        .onLongPressGesture(minimumDuration: 0.4) { openEditor(.stickers) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Mitgliedskarte"))
        .accessibilityValue(Text(verbatim: MemberCardFace.summary(status: status)))
        .accessibilityHint(Text("Tippen, um die Karte umzudrehen. Lange drücken zum Bearbeiten."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { show.flip(reduceMotion: reduceMotion) }
        .accessibilityAction(named: Text("Karte bearbeiten")) { openEditor(.stickers) }
        .accessibilityAction(named: Text("Unterschreiben")) { openEditor(.signature) }
        .accessibilityIdentifier("settings.memberCard")
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            cardWidth = max(min(Self.maxCardWidth, width), 1)
        }
        .task(id: editorTab == nil) {
            guard editorTab == nil else { return }
            await show.motion.run(reduceMotion: reduceMotion)
        }
        .task {
            loadPlacements()
            await playPendingMoments()
        }
        .onChange(of: status.style, initial: true) { style = status.style }
        .onChange(of: SupporterStore.shared.isSupporter) { if editorTab == nil { refresh() } }
        .onChange(of: ClubRewardStore.shared.redeemed) { if editorTab == nil { refresh() } }
        .sheet(item: $editorTab, onDismiss: refresh) { tab in
            MemberCardEditor(initialTab: tab, status: status, backStats: backStats)
        }
        .sheet(isPresented: $showsLab) {
            MemberCardLab()
        }
    }

    private static func unseenTierUp(_ status: MemberStatus) -> MemberTier? {
        let seen = UserDefaults.standard.string(forKey: seenTierKey).flatMap(MemberTier.init) ?? .member
        return !ScreenshotMode.active && status.tier > seen ? seen : nil
    }

    private static func hasUnseenStamp(_ status: MemberStatus) -> Bool {
        !ScreenshotMode.active && status.years > UserDefaults.standard.integer(forKey: seenYearsKey)
    }

    private func openEditor(_ tab: MemberCardEditor.Tab) {
        Haptics.land()
        editorTab = tab
    }

    private func refresh() {
        loadPlacements()
        let previous = status
        status = .current()
        backStats = MemberCardBackStat.all(for: status)
        guard status.tier != previous.tier || status.years != previous.years else { return }
        show.stampHidden = Self.hasUnseenStamp(status)
        show.revealFrom = Self.unseenTierUp(status)
        Task { await playPendingMoments() }
    }

    private func loadPlacements() {
        placements = MemberCardStickerStore().load().filter { MemberCardStickerCatalog.assets.contains($0.assetName) }
    }

    private func surface(style: MemberTier) -> some View {
        var shown = status
        shown.style = style
        return MemberCardSurface(
            status: shown,
            hidesNewestStamp: show.stampHidden && style == status.style,
            slamTrigger: show.slamTrigger,
            width: cardWidth,
            motion: show.motion,
            placements: placements
        )
    }

    private func playPendingMoments() async {
        let defaults = UserDefaults.standard
        let tierUpFrom = Self.unseenTierUp(status)
        let needsTierUp = tierUpFrom != nil
        let needsStamp = show.stampHidden
        if !needsTierUp { defaults.set(status.tier.rawValue, forKey: Self.seenTierKey) }
        if !needsStamp { defaults.set(status.years, forKey: Self.seenYearsKey) }
        guard needsTierUp || needsStamp else { return }
        try? await Task.sleep(for: .milliseconds(650))
        if let tierUpFrom {
            defaults.removeObject(forKey: MemberStatus.styleKey)
            status.style = status.tier
            await show.playTierUp(from: tierUpFrom, reduceMotion: reduceMotion)
            defaults.set(status.tier.rawValue, forKey: Self.seenTierKey)
            try? await Task.sleep(for: .milliseconds(250))
        }
        if needsStamp {
            await show.playStamp(reduceMotion: reduceMotion)
            defaults.set(status.years, forKey: Self.seenYearsKey)
        }
    }
}
