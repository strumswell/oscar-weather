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
    @State private var titleTaps: [Date] = []
    @AppStorage(MemberStatus.titleKey) private var chosenTitle: String?
    @AppStorage(MemberStatus.styleKey) private var chosenStyle: String?
    @AppStorage(MemberStatus.handleKey) private var handle = ""
    @FocusState private var handleFocused: Bool

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
            .background { MemberCardGlow(style: status.style) }
            .navigationTitle(Text("Deine Karte"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Deine Karte")
                        .font(.headline)
                        .contentShape(.rect)
                        .onTapGesture(perform: titleTapped)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                }
            }
            .sheet(isPresented: $showsLab) {
                MemberCardLab()
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: tab) {
            Haptics.tick()
        }
        .task {
            try? await ShaderLibrary.memberCardPaper().compile(as: .colorEffect)
        }
        .onChange(of: strokes) {
            UserDefaults.standard.set(MemberCardSignature.encode(strokes), forKey: MemberCard.signatureKey)
        }
    }

    private var tabs: [Tab] {
        Tab.allCases.filter { $0 != .style || status.styles.count > 1 }
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
                    ForEach(status.styles, id: \.self, content: styleChip)
                }
                .frame(width: width)
                hint(Text("Deine Stufe bleibt gleich, nur das Aussehen ändert sich."))
            }
        case .title:
            VStack(spacing: 20) {
                if status.style == .atmosphere {
                    handleField
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    titleChip(id: nil, name: Text("Ohne Titel"), rule: Text("Nur Stufe und Datum"), isEarned: true)
                    ForEach(secretTitles, id: \.self) { title in
                        titleChip(id: title, name: Text(verbatim: MemberTitle.displayName(for: title)), rule: Text("Mit Code freigeschaltet"), isEarned: true)
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
            chosenStyle = style.rawValue
            withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
                status = .current()
            }
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

    private var handleField: some View {
        let isSelected = !handle.isEmpty && status.title == "@" + handle
        return HStack(spacing: 2) {
            Text(verbatim: "@")
                .foregroundStyle(.secondary)
            TextField(text: $handle, prompt: Text(verbatim: "name.bsky.social")) {
                Text("Bluesky-Handle")
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .submitLabel(.done)
            .focused($handleFocused)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .font(.headline)
        .fontDesign(.rounded)
        .modifier(MemberCardChipBackground(isSelected: isSelected))
        .onChange(of: handle) {
            let cleaned = String(handle.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }.prefix(40))
            if cleaned != handle { handle = cleaned }
        }
        .task(id: handle) {
            guard handleFocused else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            selectHandle()
        }
        .onChange(of: handleFocused) {
            if handleFocused { selectHandle() }
        }
    }

    private func selectHandle() {
        let id = handle.isEmpty ? nil : "@" + handle
        guard id != nil || status.title?.hasPrefix("@") == true else { return }
        chosenTitle = id ?? ""
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
            status.title = id
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
                .lineLimit(1)
                .minimumScaleFactor(0.6)
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
                .modifier(MemberCardChipBackground(isSelected: isSelected))
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

struct MemberCardChipBackground: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
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
}

extension MemberTier {
    var accent: Color {
        switch self {
        case .member: Color(hex: 0x6C9DDD)
        case .supporter: Color(hex: 0xF49A5A)
        case .founder, .founderSupporter: Color(hex: 0xB69BFF)
        case .atmosphere: Color(hex: 0x3D9BFF)
        }
    }
}

struct MemberCardGlow: View {
    let style: MemberTier

    var body: some View {
        RadialGradient(colors: [style.accent.opacity(0.32), .clear], center: .top, startRadius: 0, endRadius: 460)
            .ignoresSafeArea()
            .animation(.smooth, value: style)
    }
}
