import Foundation
import Security

/// BYOK helper: stores the user's Anthropic API key (or any small secret) in
/// the Keychain as a generic password, namespaced per app by `service`.
///
/// The same pattern lived in Le Bilan, Mimésis, Le Porte-voix... — this is the
/// one shared version. Works on macOS and iOS (Security.framework is common).
///
/// ```swift
/// let store = KeychainStore(service: "com.jac.MonApp")
/// store.save("sk-ant-...")
/// let key = store.load()
/// store.delete()
/// ```
public struct KeychainStore: Sendable {
    /// The `kSecAttrService` namespace — use your app's bundle id.
    public let service: String
    /// The `kSecAttrAccount` under which the secret is filed.
    public let account: String

    /// The conventional account name for the Anthropic API key.
    public static let apiKeyAccount = "anthropic.apiKey"

    public init(service: String, account: String = KeychainStore.apiKeyAccount) {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Save (upsert) the secret. An empty string deletes the item instead.
    /// - Returns: true on success.
    @discardableResult
    public func save(_ value: String) -> Bool {
        // Delete-then-add is the simplest reliable upsert.
        SecItemDelete(baseQuery as CFDictionary)
        guard !value.isEmpty else { return true }

        var add = baseQuery
        add[kSecValueData as String] = Data(value.utf8)
        #if os(iOS)
        // On iOS the item should survive reboots but stay device-protected.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        #endif
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// Load the secret, or nil when absent / unreadable.
    public func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    /// Remove the secret. Succeeds silently when it was already absent.
    /// - Returns: true when the item was deleted or did not exist.
    @discardableResult
    public func delete() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// True when a non-empty secret is stored — cheap enough for UI checks
    /// ("show the add-your-key note?").
    public var hasValue: Bool {
        load()?.isEmpty == false
    }
}
