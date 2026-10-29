import SwiftUI

struct MemberCardEditor: View {
    enum Tab: String, Identifiable, CaseIterable {
        case stickers, style, title, signature

        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .stickers: "Sticker"
            case .style: "Stil"
            case .title: "Titel"
            case .signature: "Unterschrift"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab
    @State private var status: MemberStatus
    @State private var backStats: [MemberCardBackStat]
    @State private var motion = MemberCardMotion()
    @State private var strokes = MemberCardSignature.decode(UserDefaults.standard.data(forKey: MemberCard.signatureKey) ?? Data())
    @State private var width: CGFloat = 340
    @State private var showsLab = false
    @State private var showsVoucher = false
    @State private var titleTaps: [Date] = []
    @AppStorage(MemberStatus.titleKey) private var chosenTitle: String?
    @AppStorage(MemberStatus.styleKey) private var chosenStyle: String?

    init(initialTab: Tab, status: MemberStatus, backStats: [MemberCardBackStat]) {
        _tab = State(initialValue: initialTab)
        _status = State(initialValue: status)
        _backStats = State(initialValue: backStats)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Picker(selection: $tab.animation(.snappy)) {
                        ForEach(tabs) { tab in
                            Text(tab.label).tag(tab)
                        }
                    } label: {
                        Text("Bereich")
                    }
                    .pickerStyle(.segmented)

                    card

                    tabContent
                        .id(tab)
                        .transition(.blurReplace)
                }
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available in
                    width = max(min(available, MemberCard.maxCardWidth), 1)
                }
                .padding(20)
            }
            .scrollDisabled(tab == .stickers || tab == .signature)
            .background { glow }
            .navigationTitle(Text("Deine Karte"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Deine Karte")
                        .font(.headline)
                        .contentShape(.rect)
                        .onTapGesture(perform: titleTapped)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsVoucher = true
                    } label: {
                        Image(systemName: "ticket")
                    }
                    .accessibilityLabel(Text("Gutschein einlösen"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                }
            }
            .sheet(isPresented: $showsLab) {
                MemberCardLab()
            }
            .navigationDestination(isPresented: $showsVoucher) {
                ClubVoucherView()
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: tab) {
            Haptics.tick()
        }
        .onChange(of: showsVoucher) {
            guard !showsVoucher else { return }
            status = .current()
            backStats = MemberCardBackStat.all(for: status)
        }
        .onChange(of: strokes) {
            UserDefaults.standard.set(MemberCardSignature.encode(strokes), forKey: MemberCard.signatureKey)
        }
    }

    private var tabs: [Tab] {
        Tab.allCases.filter { $0 != .style || status.tier.styles.count > 1 }
    }

    private var card: some View {
        MemberCardFlip(angle: tab == .signature ? 180 : 0) {
            MemberCardStickerEditor(status: status, width: width, motion: motion, isActive: tab == .stickers)
        } back: {
            MemberCardBack(
                tier: status.style,
                stats: backStats,
                signature: strokes,
                width: width,
                motion: motion,
                onSignatureTap: {}
            )
            .modifier(MemberCardShadow(motion: motion, cornerRadius: MemberCardPalette.cornerRadius(for: width)))
        }
        .animation(.spring(duration: 0.7, bounce: 0.3), value: tab == .signature)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .stickers:
            hint(Text("Halte einen Sticker gedrückt und zieh ihn auf die Karte. Zum Entfernen wieder nach unten ziehen."))
        case .style:
            VStack(spacing: 20) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    ForEach(status.tier.styles, id: \.self, content: styleChip)
                }
                .frame(width: width)
                hint(Text("Deine Stufe bleibt gleich, nur das Aussehen ändert sich."))
            }
        case .title:
            VStack(spacing: 20) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    titleChip(id: nil, name: Text("Ohne Titel"), rule: Text("Nur Stufe und Datum"), isEarned: true)
                    ForEach(secretTitles, id: \.self) { title in
                        titleChip(id: title, name: Text(verbatim: title), rule: Text("Mit Code freigeschaltet"), isEarned: true)
                    }
                    ForEach(MemberTitle.all) { title in
                        titleChip(
                            id: title.id,
                            name: Text(title.name),
                            rule: Text(title.rule(SettingService.shared.units)),
                            isEarned: status.earnedTitles.contains(title.id)
                        )
                    }
                }
                hint(Text("Titel sammelst du mit der Zeit, einfach indem du Oscar benutzt."))
            }
        case .signature:
            VStack(spacing: 16) {
                MemberCardSignaturePad(strokes: $strokes)
                    .frame(width: width, height: width / MemberCardInk.aspect)
                hint(Text("Unterschreib mit dem Finger, die Unterschrift landet auf der Rückseite."))
            }
        }
    }

    private var glow: some View {
        let color = switch status.style {
        case .member: Color(hex: 0x6C9DDD)
        case .supporter: Color(hex: 0xF49A5A)
        case .founder, .founderSupporter: Color(hex: 0xB69BFF)
        }
        return RadialGradient(colors: [color.opacity(0.32), .clear], center: .top, startRadius: 0, endRadius: 460)
            .ignoresSafeArea()
    }

    private var secretTitles: [String] {
        status.earnedTitles.filter { title in !MemberTitle.all.contains { $0.id == title } }
    }

    private func titleTapped() {
        let now = Date.now
        titleTaps = titleTaps.filter { now.timeIntervalSince($0) < 2 } + [now]
        guard titleTaps.count >= 5, TestFlightMembership.showsLab else { return }
        titleTaps = []
        Haptics.success()
        showsLab = true
    }

    private func styleChip(_ style: MemberTier) -> some View {
        let isSelected = status.style == style
        var preview = status
        preview.style = style
        return chip(isSelected: isSelected) {
            Haptics.tick()
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                status.style = style
            }
            chosenStyle = style.rawValue
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                MemberCardFace(
                    tier: style,
                    title: preview.title,
                    since: preview.since,
                    stamps: preview.stamps,
                    hiddenStampID: nil,
                    slamTrigger: 0,
                    width: (width - 12) / 2 - 28,
                    motion: motion
                )
                .accessibilityHidden(true)
                chipName(Text(verbatim: style.styleName), isSelected: isSelected)
            }
        }
    }

    private func titleChip(id: String?, name: Text, rule: Text, isEarned: Bool) -> some View {
        chip(isSelected: status.title == id) {
            Haptics.tick()
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                status.title = id
            }
            chosenTitle = id ?? ""
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                chipName(name, isSelected: status.title == id)
                rule
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 74, alignment: .topLeading)
        }
        .opacity(isEarned ? 1 : 0.4)
        .disabled(!isEarned)
        .accessibilityValue(isEarned ? Text(verbatim: "") : Text("Noch nicht verdient"))
    }

    private func chipName(_ name: Text, isSelected: Bool) -> some View {
        HStack(alignment: .top) {
            name
                .font(.headline)
                .fontDesign(.rounded)
            Spacer(minLength: 4)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.headline)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func chip(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            label()
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(.white.opacity(0.14)) : AnyShapeStyle(.quaternary.opacity(0.6)))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
                }
                .scaleEffect(isSelected ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func hint(_ text: Text) -> some View {
        text
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: width)
    }
}
