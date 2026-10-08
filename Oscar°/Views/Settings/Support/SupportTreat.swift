import SwiftUI

/// What a support tier would buy, shown on the tile instead of a plain heart.
/// Generic names only (no brands); the sticker does the hinting.
/// A purchase: every reel rolls onto the bought treat. `id` makes each
/// purchase a new event, even for the same treat.
struct SupportJackpot: Equatable {
    let id: Int
    let treat: SupportTreat
}

struct SupportTreat: Identifiable, Equatable {
    let id: String
    let image: String
    let name: LocalizedStringResource
    let thanks: LocalizedStringResource

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    /// A random treat for the product, never `current` again when there is a choice.
    static func pick(for productID: String, excluding current: SupportTreat? = nil) -> SupportTreat {
        let pool = catalog[productID] ?? []
        let fresh = pool.filter { $0 != current }
        return (fresh.isEmpty ? pool : fresh).randomElement() ?? fallback
    }

    static let allImages = Set(catalog.values.joined().map(\.image))

    static let fallback = SupportTreat(id: "mate.3", image: "treat_mate", name: "3 Mate", thanks: "Prost! 3 Mate sind kalt gestellt.")

    static let catalog: [String: [SupportTreat]] = [
        "cloud.bolte.Oscar.tip.small": [
            fallback,
            SupportTreat(id: "gummies.3", image: "treat_gummies", name: "3 Tüten Gummibärchen", thanks: "3 Tüten Gummibärchen. Die roten esse ich zuerst."),
            SupportTreat(id: "fruitgums.2", image: "treat_fruitgums", name: "2 Tüten Fruchtgummi", thanks: "Die Fruchtgummis grinsen schon."),
            SupportTreat(id: "water.4", image: "treat_water", name: "4 Flaschen Sprudel", thanks: "Prost! 4 Flaschen Sprudel stehen im Kühlschrank."),
            SupportTreat(id: "cola.3", image: "treat_cola", name: "3 Dosen Cola ohne Zucker", thanks: "Zisch. Die erste Dose ist schon offen."),
            SupportTreat(id: "icetea.3", image: "treat_icetea", name: "3 Flaschen Eistee", thanks: "Prost! 3 Flaschen Eistee sind kalt gestellt."),
            SupportTreat(id: "noodles.2", image: "treat_noodles", name: "2 Becher Instant-Nudeln", thanks: "Das Wasser kocht. Noch 5 Minuten."),
            SupportTreat(id: "pasta.2", image: "treat_pasta", name: "2 Packungen gute Pasta", thanks: "Das Nudelwasser ist gesalzen."),
            SupportTreat(id: "peasoup.2", image: "treat_peasoup", name: "2 Dosen Erbsensuppe", thanks: "Erbsensuppe für zwei Regentage."),
            SupportTreat(id: "potatosoup.1", image: "treat_potatosoup", name: "1 Dose Kartoffelsuppe", thanks: "Kartoffelsuppe für den nächsten Nieselregen."),
            SupportTreat(id: "sorbet.1", image: "treat_sorbet", name: "1 Zitronensorbet", thanks: "Ein Zitronensorbet, bevor die Sonne es holt."),
            SupportTreat(id: "chocolate.1", image: "treat_chocolate", name: "1 Tafel Schokolade für Oma", thanks: "Oma freut sich. Und teilt vielleicht."),
            SupportTreat(id: "schnitzel.1", image: "treat_schnitzel", name: "1 Packung Soja-Schnitzel", thanks: "Die Pfanne ist heiß."),
            SupportTreat(id: "chips.1", image: "treat_chips", name: "1 Tüte Riffelchips", thanks: "Knack. Die Tüte ist offen."),
            SupportTreat(id: "pills.1", image: "treat_pills", name: "1 Packung Paracetamol", thanks: "Für den nächsten Bug. Danke."),
            SupportTreat(id: "sundae.1", image: "treat_sundae", name: "1 Softeis mit Karamell", thanks: "Extra viel Karamell. Danke!"),
        ],
        "cloud.bolte.Oscar.tip.medium": [
            SupportTreat(id: "mate.7", image: "treat_mate", name: "7 Mate", thanks: "Prost! 7 Mate, das reicht für eine Woche."),
            SupportTreat(id: "gummies.8", image: "treat_gummies", name: "8 Tüten Gummibärchen", thanks: "8 Tüten Gummibärchen. Ich teile nicht."),
            SupportTreat(id: "pralines.1", image: "treat_pralines", name: "Pralinen für Oma", thanks: "Oma sagt danke. Ich auch."),
            SupportTreat(id: "friedrice.1", image: "treat_friedrice", name: "1 Portion gebratener Reis", thanks: "Gebratener Reis ist bestellt. Danke!"),
            SupportTreat(id: "salami.2", image: "treat_salami", name: "2 französische Salamis", thanks: "Merci! 2 Salamis hängen in der Küche."),
            SupportTreat(id: "lasagne.3", image: "treat_lasagne", name: "3 Tiefkühl-Lasagne", thanks: "Der Ofen läuft."),
            SupportTreat(id: "pasta.5", image: "treat_pasta", name: "5 Packungen gute Pasta", thanks: "Pasta für eine Woche. Grazie!"),
            SupportTreat(id: "noodles.7", image: "treat_noodles", name: "7 Becher Instant-Nudeln", thanks: "Mittagessen für eine Woche. Das Wasser kocht."),
            SupportTreat(id: "burgermeal.1", image: "treat_burgermeal", name: "1 Burger-Menü", thanks: "Mit Pommes. Danke!"),
            SupportTreat(id: "peasoup.5", image: "treat_peasoup", name: "5 Dosen Erbsensuppe", thanks: "Erbsensuppe für eine ganze Regenwoche."),
            SupportTreat(id: "bento.1", image: "treat_bento", name: "1 Karaage-Bento", thanks: "Itadakimasu! Das Bento ist bestellt."),
            SupportTreat(id: "streaming.1", image: "treat_scifi", name: "1 Monat Streaming", thanks: "Die nächste Folge läuft schon. Danke!"),
        ],
        "cloud.bolte.Oscar.tip.large": [
            SupportTreat(id: "matecrate.1", image: "treat_matecrate", name: "1 Kasten Mate", thanks: "Prost! Der Kasten Mate steht im Flur."),
            SupportTreat(id: "cinema.1", image: "treat_cinema", name: "1 Kinoabend mit Popcorn", thanks: "Popcorn salzig, bitte. Danke für den Kinoabend!"),
            SupportTreat(id: "burger.1", image: "treat_burger", name: "1 Burger mit Pommes im Restaurant", thanks: "Mit extra Käse. Danke!"),
            SupportTreat(id: "lasagne.2", image: "treat_lasagne", name: "2 Lasagne beim Italiener", thanks: "Grazie! Der Tisch für zwei ist reserviert."),
            SupportTreat(id: "gummies.21", image: "treat_gummies", name: "21 Tüten Gummibärchen", thanks: "21 Tüten Gummibärchen. Das wird ein Problem. Danke!"),
            SupportTreat(id: "watercrate.2", image: "treat_watercrate", name: "2 Kästen Sprudel", thanks: "Prost! Zwei Kästen Sprudel, das Treppenhaus schafft das."),
        ],
        "cloud.bolte.Oscar.supporter.monthly": [
            SupportTreat(id: "water.monthly", image: "treat_water", name: "1 Sprudel im Monat", thanks: "Jeden Monat ein Sprudel. Prost!"),
            SupportTreat(id: "cola.monthly", image: "treat_cola", name: "1 Cola ohne Zucker im Monat", thanks: "Jeden Monat eine Dose. Zisch!"),
            SupportTreat(id: "gummies.monthly", image: "treat_gummies", name: "1 Tüte Gummibärchen im Monat", thanks: "Jeden Monat Gummibärchen. Danke!"),
            SupportTreat(id: "noodles.monthly", image: "treat_noodles", name: "1 Becher Instant-Nudeln im Monat", thanks: "Jeden Monat ein warmes Mittagessen."),
        ],
        "cloud.bolte.Oscar.supporter.yearly": [
            SupportTreat(id: "mate.yearly", image: "treat_mate", name: "6 Mate im Jahr", thanks: "6 Mate im Jahr. Prost!"),
            SupportTreat(id: "pralines.yearly", image: "treat_pralines", name: "Pralinen für Oma, jedes Jahr", thanks: "Oma hat jetzt ein Abo."),
            SupportTreat(id: "sundae.yearly", image: "treat_sundae", name: "3 Softeis im Jahr", thanks: "Drei Softeis für die heißesten Tage."),
        ],
    ]
}
