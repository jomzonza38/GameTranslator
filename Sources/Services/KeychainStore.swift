import Foundation
import Security

/// Minimal wrapper around the macOS Keychain for storing API keys as generic passwords.
enum KeychainStore {
    static let service = "com.worawalan.GameTranslator"

    /// Read a value for the given account. Returns nil if missing or unreadable.
    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                GameLog.log("Keychain read failed for \(account): \(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Store a value. An empty string deletes the entry.
    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        guard !value.isEmpty else { return delete(account) }
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "GameTranslator: \(account)"
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if status != errSecSuccess {
            GameLog.log("Keychain write failed for \(account): \(status)")
        }
        return status == errSecSuccess
    }

    @discardableResult
    static func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
