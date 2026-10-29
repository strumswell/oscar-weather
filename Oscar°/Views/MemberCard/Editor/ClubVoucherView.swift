import SwiftUI

struct ClubVoucherView: View {
    enum Phase: Equatable {
        case entry, checking, invalid, duplicate, redeemed
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var input = ""
    @State private var phase: Phase = .entry
    @State private var reward: ClubReward?
    @State private var shake = 0
    @State private var slam = 0
    @State private var showsStamp = false
    @State private var redeemedAt = Date.now
    private let store = ClubRewardStore.shared

    static let stampInk = Color(hex: 0x2B5BD7)

    private var code: String {
        ClubCodes.normalized(input)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ticket
                    .padding(.top, 28)
                if phase == .redeemed, let reward {
                    rewardList(reward)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    controls
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.never)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .safeAreaInset(edge: .bottom) {
            if phase == .redeemed {
                Button {
                    dismiss()
                } label: {
                    Text("Zur Karte")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
        .background(alignment: .topLeading) { field }
        .navigationTitle(Text("Gutschein"))
        .toolbarTitleDisplayMode(.inline)
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            isFocused = true
        }
        .onChange(of: input) {
            if input != code { input = code }
            if phase == .invalid || phase == .duplicate { phase = .entry }
        }
    }

    private var field: some View {
        TextField(text: $input) {
            Text("Gutscheincode")
        }
        .focused($isFocused)
        .keyboardType(.asciiCapable)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .submitLabel(.go)
        .onSubmit(submit)
        .disabled(phase == .checking || phase == .redeemed)
        .frame(width: 1, height: 1)
        .opacity(0.01)
    }

    private var ticket: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image("logo-oscar-cat")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 22)
                Text("Oscar° Gutschein")
                    .font(.system(.headline, design: .rounded))
            }
            codeRow
            caption
                .font(.footnote)
                .contentTransition(.opacity)
        }
        .foregroundStyle(MemberCardInk.color)
        .frame(maxWidth: .infinity)
        .frame(height: 204)
        .background {
            ClubTicketShape()
                .fill(MemberCardInk.paper)
                .colorEffect(ShaderLibrary.memberCardPaper())
                .overlay {
                    ClubTicketShape()
                        .fill(RadialGradient(colors: [.clear, .black.opacity(0.07)], center: .center, startRadius: 80, endRadius: 260))
                }
                .shadow(color: .black.opacity(0.45), radius: 18, y: 12)
        }
        .overlay(alignment: .topTrailing) {
            if phase == .redeemed {
                MemberCardSlammingStamp(spec: stampSpec, diameter: 128, trigger: slam, ink: Self.stampInk)
                    .opacity(showsStamp ? 1 : 0)
                    .padding(.top, 6)
                    .padding(.trailing, 6)
                    .allowsHitTesting(false)
            }
        }
        .rotationEffect(.degrees(phase == .redeemed ? -3.5 : -1.5))
        .keyframeAnimator(initialValue: 0.0, trigger: shake) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-10, duration: 0.06)
                CubicKeyframe(9, duration: 0.06)
                CubicKeyframe(-6, duration: 0.06)
                CubicKeyframe(4, duration: 0.06)
                CubicKeyframe(0, duration: 0.08)
            }
        }
        .contentShape(.rect)
        .onTapGesture { isFocused = true }
        .contextMenu {
            Button("Einfügen", systemImage: "doc.on.clipboard", action: paste)
        }
        .accessibilityHidden(true)
    }

    private var codeRow: some View {
        let characters = Array(code)
        return HStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { group in
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { offset in
                        codeSlot(group * 4 + offset, characters: characters)
                    }
                }
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) {
                    ClubDottedLine()
                        .stroke(MemberCardInk.color.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                        .frame(height: 1.5)
                }
            }
        }
        .font(.system(size: 26, weight: .semibold, design: .monospaced))
    }

    private func codeSlot(_ index: Int, characters: [Character]) -> some View {
        let isFilled = index < characters.count
        let isNext = index == characters.count && isFocused && phase != .redeemed
        let style: AnyShapeStyle = isNext ? AnyShapeStyle(.tint) : AnyShapeStyle(MemberCardInk.color.opacity(isFilled ? 1 : 0.25))
        return Text(verbatim: isFilled ? String(characters[index]) : "·")
            .foregroundStyle(style)
            .frame(width: 18)
    }

    @ViewBuilder
    private var caption: some View {
        switch phase {
        case .entry: Text("Code eintippen oder lange drücken zum Einfügen").opacity(0.6)
        case .checking: Text("Wird geprüft …").opacity(0.6)
        case .invalid: Text("Ungültiger Code").foregroundStyle(.red)
        case .duplicate: Text("Schon eingelöst").foregroundStyle(.red)
        case .redeemed: Text(redeemedAt, format: .dateTime.day().month().year()).opacity(0.6)
        }
    }

    private var controls: some View {
        Button(action: submit) {
            Group {
                if phase == .checking {
                    ProgressView()
                } else {
                    Text("Einlösen")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(code.count < ClubCodes.length || phase == .checking)
    }

    private func rewardList(_ reward: ClubReward) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Auf deiner Karte")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 16)
            VStack(spacing: 0) {
                ForEach(Array(Self.lines(for: reward).enumerated()), id: \.offset) { index, line in
                    if index > 0 { Divider() }
                    Text(verbatim: line)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
        }
    }

    private var stampSpec: MemberCardStampSpec {
        MemberCardStampSpec(
            id: "redeemed", shape: .rect, top: "OSCAR° CLUB", big: MemberCardStampSpec.caps(String(localized: "Eingelöst")),
            bottom: redeemedAt.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits)),
            ring: "", rotation: -14, trailing: 0, bottomInset: 0, seed: 5
        )
    }

    static func lines(for reward: ClubReward) -> [String] {
        var lines: [String] = []
        if reward.tier == "founder" { lines.append(String(localized: "Founder-Karte")) }
        if reward.tier == "supporter" { lines.append(String(localized: "Supporter-Karte")) }
        if let years = reward.years { lines.append(String(localized: "Stempel: \(years) Jahre")) }
        for title in reward.titles ?? [] { lines.append(String(localized: "Titel: \(title)")) }
        if let stickers = reward.stickers {
            lines.append(stickers.contains("*") ? String(localized: "Alle Sticker") : String(localized: "\(stickers.count) Sticker"))
        }
        if reward.icons == true { lines.append(String(localized: "Alle App-Symbole")) }
        if reward.pet == true { lines.append(String(localized: "Alles für den Kater")) }
        return lines
    }

    private func paste() {
        let pasted = ClubCodes.normalized(UIPasteboard.general.string ?? "")
        guard !pasted.isEmpty else {
            Haptics.error()
            shake += 1
            return
        }
        input = pasted
    }

    private func submit() {
        guard phase != .checking, phase != .redeemed else { return }
        guard code.count == ClubCodes.length else {
            Haptics.error()
            shake += 1
            return
        }
        phase = .checking
        let entered = code
        Task {
            let started = Date.now
            let result: Result<ClubReward, Error>
            do {
                result = .success(try await store.redeem(entered))
            } catch {
                result = .failure(error)
            }
            let remaining = 0.6 - Date.now.timeIntervalSince(started)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            switch result {
            case .success(let reward):
                await celebrate(reward)
            case .failure(ClubCodes.Failure.alreadyRedeemed):
                Haptics.error()
                phase = .duplicate
                shake += 1
            case .failure:
                Haptics.error()
                phase = .invalid
                shake += 1
            }
        }
    }

    private func celebrate(_ reward: ClubReward) async {
        isFocused = false
        redeemedAt = .now
        self.reward = reward
        withAnimation(.spring(duration: 0.5, bounce: 0.25)) { phase = .redeemed }
        try? await Task.sleep(for: .milliseconds(450))
        showsStamp = true
        guard !reduceMotion else {
            Haptics.success()
            return
        }
        slam += 1
        try? await Task.sleep(for: .milliseconds(Int(MemberCardStampSlam.impact * 1000)))
        Haptics.stamp()
        try? await Task.sleep(for: .milliseconds(250))
        Haptics.success()
    }
}

private struct ClubDottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

struct ClubTicketShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 13
        var notches = Path()
        notches.addEllipse(in: CGRect(x: rect.minX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2))
        notches.addEllipse(in: CGRect(x: rect.maxX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2))
        return Path(roundedRect: rect, cornerRadius: 14, style: .continuous).subtracting(notches)
    }
}
