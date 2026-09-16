import SwiftUI

struct SupportIntro: View {
    let isSupporter: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isSupporter {
                Text("Danke, dass du Oscar unterstützt.")
                    .font(.title.bold())
                Text("Alle App-Symbole und Sticker sind für dich freigeschaltet.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Oscar unterstützen")
                    .font(.title.bold())
                Text("Ich entwickle Oscar alleine in meiner Freizeit und trage jegliche Kosten aus eigener Tasche. Durch deine Unterstützung kann ich Oscar betreiben und weiterentwickeln. Zahl was du kannst und erhalte dafür als Dankeschön Zugriff auf eine wachsende Anzahl an App-Icons und Sticker.")
                    .foregroundStyle(.secondary)
                Text(verbatim: "– Philipp")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }
}
