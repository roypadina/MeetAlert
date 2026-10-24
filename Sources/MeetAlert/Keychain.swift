import Foundation
import Security

/// Generic-password items for the ntfy secrets (access token, fallback topic URL): never in config.json.
enum Keychain {
    static let tokenService = "com.roy.meetalert.ntfy-token"
    static let fallbackService = "com.roy.meetalert.ntfy-fallback"

    private static func query(_ service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "meetalert"]
    }

    static func get(_ service: String) -> String {
        var q = query(service)
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Empty value deletes the item.
    static func set(_ service: String, _ value: String) {
        guard get(service) != value else { return }
        SecItemDelete(query(service) as CFDictionary)
        guard !value.isEmpty else { return }
        var q = query(service)
        q[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}
