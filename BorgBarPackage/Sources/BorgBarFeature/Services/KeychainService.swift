import Foundation
import Security

public actor KeychainService {
    public init() {}

    public func setPassphrase(repoID: String, passphrase: String) throws {
        let account = "BorgBar"
        let service = "borgbar-repo-\(repoID)"
        let data = Data(passphrase.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service
        ]

        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BackupError.preflightFailed("Could not save passphrase to Keychain (\(status))")
        }
    }

    public func hasPassphrase(repoID: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "BorgBar",
            kSecAttrService as String: "borgbar-repo-\(repoID)",
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    public func passCommand(repoID: String) -> String {
        "security find-generic-password -a BorgBar -s borgbar-repo-\(repoID) -w"
    }
}
