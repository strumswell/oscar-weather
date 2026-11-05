import SwiftUI

struct SupportIntro: View {
    let isSupporter: Bool
    var isAsking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isSupporter {
                Text("Danke, dass du Oscar unterstützt.")
                    .font(.title.bold())
                Text("App-Icons, Sticker, das klassische Design, Möbel für Oscar und die Supporter-Karte sind für dich freigeschaltet.")
                    .foregroundStyle(.secondary)
            } else if isAsking {
                Text("Oscar ist kostenlos")
                    .font(.title.bold())
                Text("Für mich als einzelnen Entwickler kostet der Betrieb aber jeden Monat einiges. Wenn dir Oscar gefällt, hilft jede Unterstützung.")
                    .foregroundStyle(.secondary)
                Text(verbatim: "– Philipp")
                    .foregroundStyle(.secondary)
            } else {
                Text("Oscar unterstützen")
                    .font(.title.bold())
                Text("Ich entwickle Oscar alleine in meiner Freizeit und trage jegliche Kosten aus eigener Tasche. Durch deine Unterstützung kann ich Oscar betreiben und weiterentwickeln. Zahl was du kannst, einmalig oder regelmäßig mit einem Abo. Als Dankeschön schaltest du App-Icons, Sticker, das klassische Design, Möbel für Oscar und die Supporter-Karte frei.")
                    .foregroundStyle(.secondary)
                Text(verbatim: "– Philipp")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }
}
