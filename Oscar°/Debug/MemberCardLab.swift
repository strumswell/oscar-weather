import SwiftUI

struct MemberCardLab: View {
    enum TiltMode: String, CaseIterable, Identifiable {
        case float = "Schweben"
        case live = "Gyro"
        case manual = "Manuell"
        case still = "Ruhig"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var show = MemberCardShow()
    @State private var tier: MemberTier = .founderSupporter
    @State private var years = 3
    @State private var title = "Minus 20 Club"
    @State private var tiltMode: TiltMode = .float
    @State private var manualTilt = CGSize.zero
    @State private var tierUpFrom: MemberTier = .member
    @State private var reduceMotion = false

    private let width: CGFloat = 340

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    cardPreview
                    cardSection
                    tiltSection
                    momentSection
                    tierGallery
                    stampSection
                }
                .padding(20)
            }
            .background(Color(hex: 0x101114))
            .navigationTitle(Text(verbatim: "Kartenlabor"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .task(id: tiltMode) {
                applyTiltMode()
                await show.motion.run(reduceMotion: false)
            }
            .onChange(of: manualTilt) { applyTiltMode() }
        }
        .preferredColorScheme(.dark)
    }

    private var cardPreview: some View {
        MemberCardStage(show: show, tier: tier, width: width, tiltActive: true) { tier in
            face(tier, width: width, animated: true)
        } back: {
            MemberCardBack(
                tier: tier,
                stats: Self.sampleStats(founder: tier.isFounder),
                signature: [],
                width: width,
                motion: show.motion,
                onSignatureTap: {}
            )
        }
        .frame(width: width, height: width / MemberCardPalette.aspect)
        .onTapGesture { show.flip(reduceMotion: reduceMotion) }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var cardSection: some View {
        section("Karte") {
            Picker(selection: $tier) {
                ForEach(MemberTier.allCases, id: \.self) { tier in
                    Text(verbatim: Self.label(tier)).tag(tier)
                }
            } label: {
                Text(verbatim: "Stufe")
            }
            .pickerStyle(.segmented)
            Stepper(value: $years, in: 0...15) {
                Text(verbatim: "Jahre: \(years)")
            }
            Picker(selection: $title) {
                Text(verbatim: "Kein Titel").tag("")
                ForEach(MemberTitle.all) { title in
                    Text(verbatim: title.id).tag(title.id)
                }
            } label: {
                Text(verbatim: "Titel")
            }
        }
    }

    private var tiltSection: some View {
        section("Neigung") {
            Picker(selection: $tiltMode) {
                ForEach(TiltMode.allCases) { mode in
                    Text(verbatim: mode.rawValue).tag(mode)
                }
            } label: {
                Text(verbatim: "Neigung")
            }
            .pickerStyle(.segmented)
            if tiltMode == .manual {
                Slider(value: $manualTilt.width, in: -1...1) { Text(verbatim: "X") }
                Slider(value: $manualTilt.height, in: -1...1) { Text(verbatim: "Y") }
                HStack {
                    labButton("Max ↖") { manualTilt = CGSize(width: -1, height: -1) }
                    labButton("Max ↘") { manualTilt = CGSize(width: 1, height: 1) }
                    labButton("Mitte") { manualTilt = .zero }
                }
            }
        }
    }

    private var momentSection: some View {
        section("Momente") {
            Toggle(isOn: $reduceMotion) { Text(verbatim: "Bewegung reduzieren") }
            HStack {
                labButton("Umdrehen") { show.flip(reduceMotion: reduceMotion) }
                labButton("Glanz") { show.motion.sweep() }
                labButton("Stempel") { playStamp() }
            }
            HStack {
                Picker(selection: $tierUpFrom) {
                    ForEach(MemberTier.allCases, id: \.self) { tier in
                        Text(verbatim: Self.label(tier)).tag(tier)
                    }
                } label: {
                    Text(verbatim: "Von")
                }
                labButton("Tier-Up") {
                    Task { await show.playTierUp(from: tierUpFrom, reduceMotion: reduceMotion) }
                }
            }
            labButton("Alle Momente zurücksetzen") {
                UserDefaults.standard.removeObject(forKey: MemberCard.seenTierKey)
                UserDefaults.standard.removeObject(forKey: MemberCard.seenYearsKey)
            }
        }
    }

    private var tierGallery: some View {
        section("Alle Stufen") {
            ForEach(MemberTier.allCases, id: \.self) { tier in
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: Self.label(tier))
                        .font(.subheadline.weight(.semibold))
                    face(tier, width: width, animated: false)
                        .modifier(MemberCardShadow(motion: show.motion, cornerRadius: MemberCardPalette.cornerRadius(for: width)))
                        .modifier(MemberCardTiltEffect(motion: show.motion, isActive: true))
                        .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 16)
            }
        }
    }

    private var stampSection: some View {
        section("Stempel") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 18) {
                ForEach(Self.stampGallery.indices, id: \.self) { index in
                    MemberCardStamp(spec: Self.stampGallery[index], diameter: 92)
                        .rotationEffect(.degrees(Self.stampGallery[index].rotation))
                }
            }
            .padding(.vertical, 18)
            .background {
                MemberCardMaterial(tier: .member)
                    .clipShape(.rect(cornerRadius: 16))
            }
        }
    }

    private func face(_ tier: MemberTier, width: CGFloat, animated: Bool) -> some View {
        let stamps = MemberCardStampSpec.specs(tier: tier, years: years, seed: 0.37)
        return MemberCardFace(
            tier: tier,
            title: title.isEmpty ? nil : title,
            since: Calendar.current.date(byAdding: .day, value: -(years * 365 + 40), to: .now) ?? .now,
            stamps: stamps,
            hiddenStampID: animated && show.stampHidden && tier == self.tier ? stamps.last?.id : nil,
            slamTrigger: animated ? show.slamTrigger : 0,
            width: width,
            motion: show.motion
        )
    }

    private func playStamp() {
        if years == 0 { years = 1 }
        show.stampHidden = true
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            await show.playStamp(reduceMotion: reduceMotion)
        }
    }

    private func applyTiltMode() {
        switch tiltMode {
        case .float:
            show.motion.manualTilt = nil
            show.motion.forcesFloat = true
        case .live:
            show.motion.manualTilt = nil
            show.motion.forcesFloat = false
        case .manual:
            show.motion.manualTilt = manualTilt
        case .still:
            show.motion.manualTilt = .zero
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: title)
                .font(.title3.weight(.bold))
            content()
        }
    }

    private func labButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private static func label(_ tier: MemberTier) -> String {
        tier == .founderSupporter ? "F + S" : tier.name
    }

    private static var stampGallery: [MemberCardStampSpec] {
        [1, 2, 3, 5, 10].compactMap { MemberCardStampSpec.specs(tier: .member, years: $0, seed: Double($0) * 0.29).last }
            + MemberCardStampSpec.specs(tier: .founder, years: 0, seed: 0.5)
    }

    private static func sampleStats(founder: Bool) -> [MemberCardBackStat] {
        [
            MemberCardBackStat(label: String(localized: "Mitglied seit"), value: founder ? "Beta" : "11/26"),
            MemberCardBackStat(label: String(localized: "Aktive Tage"), value: 1214.formatted()),
            MemberCardBackStat(label: String(localized: "Längste Serie"), value: Duration.seconds(141 * 86_400).formatted(.units(allowed: [.days], width: .narrow))),
            MemberCardBackStat(label: String(localized: "Kältester Moment"), value: SettingService.shared.units.preciseTemperatureString(-21.4))
        ]
    }
}
