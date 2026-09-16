import Foundation
import OSLog
import Security

/// Generic-password items under one service. Items are readable after the first
/// unlock so token updates delivered while the device is locked can still be
/// patched. Items written by earlier builds carried no service attribute; `load`
/// migrates them on first read.
struct KeychainStore: Sendable {
    let service: String
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Oscar", category: "Keychain")

    private func baseQuery(key: String, legacy: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        if !legacy { query[kSecAttrService as String] = service }
        return query
    }

    func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        SecItemDelete(baseQuery(key: key) as CFDictionary)
        var attributes = baseQuery(key: key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            Self.logger.error("Keychain save failed for \(key, privacy: .public): \(status, privacy: .public)")
        }
    }

    func load(key: String) -> String? {
        if let value = read(key: key, legacy: false) { return value }
        guard let legacyValue = read(key: key, legacy: true) else { return nil }
        // The legacy query carries no service attribute, so it would also match the
        // migrated copy: delete first, then write.
        SecItemDelete(baseQuery(key: key, legacy: true) as CFDictionary)
        save(key: key, value: legacyValue)
        return legacyValue
    }

    private func read(key: String, legacy: Bool) -> String? {
        var query = baseQuery(key: key, legacy: legacy)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    func delete(key: String) {
        SecItemDelete(baseQuery(key: key) as CFDictionary)
        SecItemDelete(baseQuery(key: key, legacy: true) as CFDictionary)
    }
}
