import CommonCrypto
import CryptoKit
import Foundation

struct ClubReward: Codable, Equatable {
    var tier: String?
    var years: Int?
    var titles: [String]?
    var stickers: [String]?
    var icons: Bool?
    var pet: Bool?
    var redeemedAt: Date?
}

struct ClubUnlocks: Equatable {
    var founder = false
    var supporter = false
    var years: Int?
    var titles: [String] = []
    var stickers: Set<String> = []
    var icons = false
    var pet = false

    static let none = ClubUnlocks()

    init() {}

    init(_ rewards: [ClubReward], now: Date = .now) {
        for reward in rewards {
            founder = founder || reward.tier == "founder"
            supporter = supporter || reward.tier == "supporter"
            if let years = reward.years {
                let since = reward.redeemedAt ?? now
                let elapsed = max(0, Calendar.current.dateComponents([.year], from: since, to: now).year ?? 0)
                self.years = max(self.years ?? 0, years + elapsed)
            }
            titles += (reward.titles ?? []).filter { !titles.contains($0) }
            stickers.formUnion(reward.stickers ?? [])
            icons = icons || reward.icons == true
            pet = pet || reward.pet == true
        }
    }

    func unlocksSticker(_ asset: String) -> Bool {
        stickers.contains("*") || stickers.contains(asset)
    }
}

enum ClubCodes {
    enum Failure: Error { case unknown, alreadyRedeemed }

    static let length = 12
    private static let salt = Array("oscar.club.v1".utf8)
    private static let rounds: UInt32 = 300_000

    private static let table: [String: String] = [
        "9e6ec409fcd1f8e8f4d163a02beaac33": "EXooWYqwXZSKw4E/fL/MvRpAP56/SqWoFTWfZUbRTdSK/whSSNbW+RFcPV2tRw==",
        "b476da55500c1be6fa64f6015d401ce6": "UZ7YZ8nKYnkICvfVfo6ZYY0XuIjiL5K87R7VYsQMVY36ST84FrH412rFZ/0uDTcOepDQphsEA8gmg3exhQE4ofw=",
        "a74362085533af472911177c1926aced": "ErpjAuQJmLqOiie1zZY043/Dm/vH8r2l3yhJWOVrM5K19acunkET9rP537MbJnQZOu08cPtQx5RezTW33JL+5E1PGRATYNau",
        "b262c50fc98ffbe577f0d92942b0d4c6": "JaP5okHg+UjqlbtRREUXJDDqVEw1YzbPjzz1PAf7TTVeNx+7/0mb",
        "26d3b41cfda35287af070fe2c9594cd1": "PDA5Zey8vHQf1/xr093KIEFpbaP/kdI158TNZPZEdOgc5JIozYEH",
        "ce40558cde4b5d32bde7368e06486497": "q4mvfuJ9L9NieyObIJ/iLfxPo2pOxhaW8QwvvkyMR3utxmDT+ZGj",
        "7bacf72bf5b3e836b0c87dfc61ad0aea": "twjq4e4v0e2UL4poqfeLluju8tVFP0IizhH1uxOg8npS/UmLjK98",
        "4f0b0d443589d9779220649421260f87": "gMnPrK94AK6H67CmiXj8ysc3Sz1RU3rLmNFVHyCjgtxuZ6wZZcvI",
        "75f529720cbbde9999bb93224bc42355": "7hyCEGIVHqTM9cqWcyP625OD5H8HwYRH7aAeaBdwdDHTQ3IAiQIi",
        "6cf23d6ba72661ab5b81c2454787c1c1": "tPsLReNE78dp39gpiucgHTOMurDbBtkSYOYZU3pmPsFQ6GjkXl+1",
        "b086347d27a477c3c8ab7d7de8e3aec6": "FuH/e3izae6WWadTZ2+OZsRxKPi6nFDVk/+zmTi8QZnX4U9FKLStXBVG",
        "6d148ea60e5bd878eb82371524a0d528": "hZTDDbQeoJwkUnEQ+TocVvXh8+95Wj8GLuHymbc+umqrBiPNPDLjMQ==",
    ]

    static func normalized(_ input: String) -> String {
        String(input.uppercased().filter(\.isHexDigit).prefix(length))
    }

    static func key(for code: String) -> SymmetricKey {
        let password = Array(normalized(code).utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        _ = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password.map { Int8(bitPattern: $0) }, password.count,
            salt, salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
            &derived, derived.count
        )
        return SymmetricKey(data: derived)
    }

    static func identifier(for key: SymmetricKey) -> String {
        let digest = key.withUnsafeBytes { SHA256.hash(data: Data($0)) }
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func open(_ code: String, in table: [String: String] = table) throws -> (id: String, reward: ClubReward) {
        let key = key(for: code)
        let id = identifier(for: key)
        guard let sealed = table[id].flatMap({ Data(base64Encoded: $0) }),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let json = try? AES.GCM.open(box, using: key),
              let reward = try? JSONDecoder().decode(ClubReward.self, from: json)
        else { throw Failure.unknown }
        return (id, reward)
    }

    static func seal(_ reward: ClubReward, code: String) throws -> (id: String, box: String) {
        let key = key(for: code)
        let json = try JSONEncoder().encode(reward)
        let sealed = try AES.GCM.seal(json, using: key)
        return (identifier(for: key), sealed.combined?.base64EncodedString() ?? "")
    }
}

@MainActor
@Observable
final class ClubRewardStore {
    static let shared = ClubRewardStore()

    private(set) var redeemed: [String: ClubReward] = [:]

    private static let key = "clubRewards"
    @ObservationIgnored private let cloud = NSUbiquitousKeyValueStore.default

    var unlocks: ClubUnlocks {
        ClubUnlocks(redeemed.keys.sorted().compactMap { redeemed[$0] })
    }

    private init() {
        let decoder = JSONDecoder()
        for data in [AppGroup.defaults.data(forKey: Self.key), cloud.data(forKey: Self.key)].compactMap({ $0 }) {
            let stored = (try? decoder.decode([String: ClubReward].self, from: data)) ?? [:]
            redeemed.merge(stored) { mine, _ in mine }
        }
    }

    func redeem(_ code: String) async throws -> ClubReward {
        let result = try await Task.detached(priority: .userInitiated) { try ClubCodes.open(code) }.value
        guard redeemed[result.id] == nil else { throw ClubCodes.Failure.alreadyRedeemed }
        var reward = result.reward
        reward.redeemedAt = .now
        redeemed[result.id] = reward
        guard let data = try? JSONEncoder().encode(redeemed) else { return reward }
        AppGroup.defaults.set(data, forKey: Self.key)
        cloud.set(data, forKey: Self.key)
        return reward
    }
}
