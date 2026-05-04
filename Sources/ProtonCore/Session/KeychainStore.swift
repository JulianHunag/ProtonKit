import Foundation
import Security

public enum KeychainStore {
    private static let service = "com.protonkit.session"

    private static func namespacedKey(_ key: String, _ namespace: String?) -> String {
        namespace.map { "\($0).\(key)" } ?? key
    }

    public static func save(key: String, data: Data, namespace: String? = nil) throws {
        let nsKey = namespacedKey(key, namespace)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: nsKey,
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    public static func save(key: String, string: String, namespace: String? = nil) throws {
        guard let data = string.data(using: .utf8) else { return }
        try save(key: key, data: data, namespace: namespace)
    }

    public static func load(key: String, namespace: String? = nil) -> Data? {
        let nsKey = namespacedKey(key, namespace)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: nsKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    public static func loadString(key: String, namespace: String? = nil) -> String? {
        guard let data = load(key: key, namespace: namespace) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(key: String, namespace: String? = nil) {
        let nsKey = namespacedKey(key, namespace)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: nsKey,
        ]
        SecItemDelete(query as CFDictionary)
    }

    public static func deleteAll(namespace: String? = nil) {
        delete(key: "uid", namespace: namespace)
        delete(key: "accessToken", namespace: namespace)
        delete(key: "refreshToken", namespace: namespace)
        delete(key: "keyPassphrase", namespace: namespace)
    }

    public enum KeychainError: Error {
        case saveFailed(OSStatus)
    }
}
