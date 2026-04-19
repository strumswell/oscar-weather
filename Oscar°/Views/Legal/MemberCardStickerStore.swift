import Foundation

struct MemberCardStickerStore {
    private let defaults: UserDefaults
    private let storageKey = "memberCardStickerPlacements"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [MemberCardStickerPlacement] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }

        do {
            return try JSONDecoder().decode([MemberCardStickerPlacement].self, from: data)
        } catch {
            defaults.removeObject(forKey: storageKey)
            return []
        }
    }

    func save(_ placements: [MemberCardStickerPlacement]) {
        guard !placements.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }

        do {
            let data = try JSONEncoder().encode(placements)
            defaults.set(data, forKey: storageKey)
        } catch {
            assertionFailure("Unable to persist member card stickers: \(error.localizedDescription)")
        }
    }
}
