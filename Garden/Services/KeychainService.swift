import Foundation
import Security

enum KeychainService {
    private static let service = "com.danny.garden"
    private static let account = "anthropic_api_key"

    private static var skipKeychain: Bool {
        ProcessInfo.processInfo.environment["GARDEN_SKIP_KEYCHAIN"] != nil
            || ProcessInfo.processInfo.environment["GARDEN_ANTHROPIC_KEY"] != nil
    }

    static func save(_ key: String) {
        guard !skipKeychain else { return }

        let data = Data(key.utf8)

        // Delete existing first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard !key.isEmpty else { return }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load() -> String {
        // Environment variable takes priority — avoids keychain prompts during dev/testing
        if let envKey = ProcessInfo.processInfo.environment["GARDEN_ANTHROPIC_KEY"], !envKey.isEmpty {
            return envKey
        }

        guard !skipKeychain else { return "" }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
