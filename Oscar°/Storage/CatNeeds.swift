import Foundation

struct CatNeeds: Codable, Equatable {
    enum Mood { case sleepy, hungry, bored, happy }

    var food = 0.7
    var fun = 0.6
    var energy = 0.9
    var updated = Date.now

    static let enabledKey = "catEnabled"
    static let fastKey = "catFast"
    private static let storageKey = "catNeeds"
    private static var cloud: NSUbiquitousKeyValueStore { .default }

    mutating func add(food: Double = 0, fun: Double = 0, energy: Double = 0) {
        self.food = min(max(self.food + food, 0), 1)
        self.fun = min(max(self.fun + fun, 0), 1)
        self.energy = min(max(self.energy + energy, 0), 1)
    }

    func aged(to now: Date, speed: Double = 1) -> CatNeeds {
        let hours = max(now.timeIntervalSince(updated), 0) / 3600 * speed
        var aged = self
        aged.add(food: -hours / 16, fun: -hours / 10, energy: hours / 6)
        aged.updated = now
        return aged
    }

    func mood(isSleepTime: Bool) -> Mood {
        if energy < 0.2 || isSleepTime { return .sleepy }
        if food < 0.3 { return .hungry }
        if fun < 0.3 { return .bored }
        return .happy
    }

    static func load() -> CatNeeds {
        [UserDefaults.standard.data(forKey: storageKey), cloud.data(forKey: storageKey)]
            .compactMap { $0.flatMap { try? JSONDecoder().decode(CatNeeds.self, from: $0) } }
            .max { $0.updated < $1.updated } ?? CatNeeds()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
        Self.cloud.set(data, forKey: Self.storageKey)
    }
}
