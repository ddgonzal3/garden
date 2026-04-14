import Foundation
import Security

enum KeychainService {
    private static let service = "com.danny.garden"
    private static let account = "anthropic_api_key"
    private static let localKeyPath = NSString("~/.garden/api_key").expandingTildeInPath

    private static var skipKeychain: Bool {
        ProcessInfo.processInfo.environment["GARDEN_SKIP_KEYCHAIN"] != nil
            || ProcessInfo.processInfo.environment["GARDEN_ANTHROPIC_KEY"] != nil
    }

    // MARK: - Local file (checked first, avoids keychain permission prompts)

    private static func loadFromFile() -> String? {
        guard let data = FileManager.default.contents(atPath: localKeyPath),
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        return key
    }

    private static func saveToFile(_ key: String) {
        let dir = (localKeyPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? key.write(toFile: localKeyPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Public API

    static func save(_ key: String) {
        // Always save to local file so future loads skip keychain
        saveToFile(key)

        guard !skipKeychain else { return }

        let data = Data(key.utf8)

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
        // 1. Environment variable
        if let envKey = ProcessInfo.processInfo.environment["GARDEN_ANTHROPIC_KEY"], !envKey.isEmpty {
            return envKey
        }

        // 2. Local file (~/.garden/api_key) — no permissions needed
        if let fileKey = loadFromFile() {
            return fileKey
        }

        // 3. Keychain (fallback — may trigger permission prompt)
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
