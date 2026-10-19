import Foundation
import Security

/// Keeps server session tokens in the Keychain, one per account.
nonisolated struct Keychain: Sendable {
    let service: String

    static let serverTokens = Keychain(service: "page.chek.server-session")

    func token(for account: UUID) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account.uuidString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func setToken(_ token: String, for account: UUID) -> Bool {
        removeToken(for: account)
        let item: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account.uuidString,
            kSecValueData: Data(token.utf8),
            // Reading continues after a restart before the first unlock,
            // for downloads and syncing in the background.
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func removeToken(for account: UUID) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
