import SwiftUI

struct CatSettingsView: View {
    @AppStorage(CatNeeds.enabledKey) private var catEnabled = true
    private let supporter = SupporterStore.shared

    var body: some View {
        List {
            Section {
                CatSettingsHero(isAwake: catEnabled)
            }
            .listRowInsets(EdgeInsets())

            Section {
                Toggle("Oscar anzeigen", isOn: $catEnabled.animation())
            } footer: {
                Text("Oscar sitzt im Wetter-Tab auf den Werten unter der Temperatur.")
            }

            Section("So spielst du mit ihm") {
                CatTipRow(title: "Antippen", detail: "Öffnet sein Menü mit Fisch, Ball und Angel.") {
                    pixel("cat_fish", width: 16, height: 11, scale: 2)
                }
                CatTipRow(title: "Streicheln", detail: "Streich mit dem Finger über ihn, dann schnurrt er.") {
                    pixel("cat_heart", width: 7, height: 6, scale: 3)
                }
                CatTipRow(title: "Doppeltippen", detail: "Er springt vor Freude.") {
                    PixelSprite(sheet: "cat_ball", frames: 5, frame: 0, size: CGSize(width: 32, height: 32))
                }
                CatTipRow(title: "Wecken", detail: "Schläft er, weckt ihn ein Tipp.") {
                    pixel("cat_z", width: 5, height: 7, scale: 3)
                }
            }
            .disabled(!catEnabled)

            Section {
                if supporter.isSupporter {
                    furnitureRow
                } else {
                    NavigationLink {
                        SupportView()
                    } label: {
                        furnitureRow
                    }
                    .accessibilityValue(Text("Für Unterstützer:innen"))
                }
            } footer: {
                if !supporter.isSupporter {
                    Text("Möbel gibt es für Unterstützer:innen.")
                }
            }
            .disabled(!catEnabled)
        }
        .navigationTitle("Kater")
        .toolbarTitleDisplayMode(.inline)
    }

    private var furnitureRow: some View {
        CatTipRow(title: "Möbel", detail: "Bett, Napf und Kratzbaum stellst du über sein Menü auf. Lange drücken und ziehen verschiebt sie.") {
            pixel("cat_bowl_0", width: 16, height: 14, scale: 2)
        }
    }

    private func pixel(_ name: String, width: CGFloat, height: CGFloat, scale: CGFloat) -> some View {
        Image(name)
            .resizable()
            .interpolation(.none)
            .frame(width: width * scale, height: height * scale)
    }
}

private struct CatTipRow<Icon: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    @ViewBuilder let icon: Icon

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 14) {
            icon
                .frame(width: 44, height: 44)
                .background {
                    Image("cat_slot")
                        .resizable(capInsets: EdgeInsets(top: 6, leading: 6, bottom: 8, trailing: 6), resizingMode: .stretch)
                        .interpolation(.none)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement(children: .combine)
    }
}

private struct CatSettingsHero: View {
    let isAwake: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var anim = CatAnim.idle
    @State private var animStart = Date.now
    @State private var heartAt: Date?

    private static let scale: CGFloat = 4

    var body: some View {
        let shown = isAwake ? anim : .sleep
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { context in
            let now = context.date
            VStack(spacing: 12) {
                Image("cat_name")
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 31 * 3, height: 7 * 3)
                    .foregroundStyle(.primary)
                PixelSprite(
                    sheet: shown.sheet,
                    frames: shown.frames,
                    frame: reduceMotion ? 0 : shown.frame(after: now.timeIntervalSince(animStart)),
                    size: CGSize(width: 32 * Self.scale, height: 32 * Self.scale)
                )
                .background(alignment: .bottom) {
                    Ellipse()
                        .fill(.primary.opacity(0.08))
                        .frame(width: 88, height: 10)
                        .offset(y: 4)
                }
                .overlay(alignment: .top) {
                    burst(at: now)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .opacity(isAwake ? 1 : 0.6)
        .contentShape(.rect)
        .onTapGesture(perform: tap)
        .task(id: animStart) {
            guard anim.isOneShot, (try? await Task.sleep(for: .seconds(anim.duration))) != nil else { return }
            anim = .idle
            animStart = .now
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func burst(at now: Date) -> some View {
        if !isAwake {
            let t = reduceMotion ? 0 : now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
            glyph("cat_z", width: 5, height: 7, rise: t)
                .offset(x: 28)
        } else if let heartAt, case let t = now.timeIntervalSince(heartAt), t < 1 {
            glyph("cat_heart", width: 7, height: 6, rise: t)
        }
    }

    private func glyph(_ name: String, width: CGFloat, height: CGFloat, rise: Double) -> some View {
        Image(name)
            .renderingMode(name == "cat_z" ? .template : .original)
            .resizable()
            .interpolation(.none)
            .frame(width: width * 3, height: height * 3)
            .foregroundStyle(.secondary)
            .offset(y: 40 - rise * 30)
            .opacity(1 - rise)
    }

    private func tap() {
        guard isAwake, !anim.isOneShot else { return }
        anim = .jump
        animStart = .now
        heartAt = .now
        Haptics.land()
    }
}
