import Foundation

struct MemberCardStickerStore {
    private let defaults: UserDefaults
    private let storageKey = "memberCardStickerPlacements"

    /// Versioned so a future field can be added without wiping saved layouts.
    private struct Envelope: Codable {
        var version = 1
        var placements: [MemberCardStickerPlacement]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [MemberCardStickerPlacement] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            return envelope.placements
        }
        return (try? decoder.decode([MemberCardStickerPlacement].self, from: data)) ?? []
    }

    func save(_ placements: [MemberCardStickerPlacement]) {
        guard !placements.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(Envelope(placements: placements)), forKey: storageKey)
        } catch {
            assertionFailure("Unable to persist member card stickers: \(error.localizedDescription)")
        }
    }
}
