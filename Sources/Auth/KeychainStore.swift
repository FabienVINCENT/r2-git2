import Foundation
import Security

/// Minimal wrapper over the macOS Keychain (`kSecClassGenericPassword`) for the GitHub token.
///
/// The token is **never** written to disk in clear text or to UserDefaults. All access goes
/// through this type. It is a plain struct with no state — the Keychain is the source of truth.
struct KeychainStore: Sendable {

    /// Namespaced service so we never collide with other apps.
    private let service: String
    private let account: String

    init(service: String = "fr.fabien-vincent.r2-git2", account: String = "github-oauth-token") {
        self.service = service
        self.account = account
    }

    enum KeychainError: Error, LocalizedError {
        case unexpectedStatus(OSStatus)
        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let s):
                return "Keychain error (\(s)): \(SecCopyErrorMessageString(s, nil) as String? ?? "unknown")"
            }
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Stores (or replaces) the token. Accessible after first unlock; not synced to iCloud.
    func save(token: String) throws {
        guard let data = token.data(using: .utf8) else { return }

        // Try update first; if nothing exists, add.
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Reads the token, or nil if none is stored.
    func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Purges the token (used on Sign out). Missing item is treated as success.
    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    var hasToken: Bool { read() != nil }
}
