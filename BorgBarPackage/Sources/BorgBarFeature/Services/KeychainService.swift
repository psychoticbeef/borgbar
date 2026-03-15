import Foundation
import Security

public enum BorgPassphraseAccess: Sendable {
    case passCommand(String)
    case environmentVariable(String)
}

public struct PassphraseStorageAvailability: Sendable, Equatable {
    public let isAvailable: Bool
    public let message: String?

    public static let available = PassphraseStorageAvailability(isAvailable: true, message: nil)

    public static func unavailable(_ message: String) -> PassphraseStorageAvailability {
        PassphraseStorageAvailability(isAvailable: false, message: message)
    }
}

struct KeychainSigningEntitlements: Sendable, Equatable {
    let applicationIdentifier: String?
    let teamIdentifier: String?
    let keychainAccessGroups: [String]
}

public actor KeychainService {
    private static let account = "BorgBar"

    public init() {}

    public func availability(for storage: PassphraseStorageMode) -> PassphraseStorageAvailability {
        Self.availability(for: storage, entitlements: currentSigningEntitlements())
    }

    public func setPassphrase(repoID: String, passphrase: String, storage: PassphraseStorageMode) throws {
        try ensureAvailability(for: storage)
        let service = serviceName(repoID: repoID, storage: storage)
        let data = Data(passphrase.utf8)
        let query = baseQuery(service: service, storage: storage)

        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        if storage == .iCloudKeychain {
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        }

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw BackupError.preflightFailed(saveFailureMessage(status: status, storage: storage))
        }
    }

    public func hasPassphrase(repoID: String, storage: PassphraseStorageMode) -> Bool {
        guard availability(for: storage).isAvailable else {
            return false
        }
        var query = baseQuery(service: serviceName(repoID: repoID, storage: storage), storage: storage)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    public func passphraseAccess(repoID: String, storage: PassphraseStorageMode) throws -> BorgPassphraseAccess {
        try ensureAvailability(for: storage)
        switch storage {
        case .localKeychain:
            return .passCommand(localPassCommand(repoID: repoID))
        case .iCloudKeychain:
            return .environmentVariable(try synchronizablePassphrase(repoID: repoID))
        }
    }

    private func localPassCommand(repoID: String) -> String {
        "security find-generic-password -a \(Self.account) -s \(serviceName(repoID: repoID, storage: .localKeychain)) -w"
    }

    private func synchronizablePassphrase(repoID: String) throws -> String {
        var query = baseQuery(
            service: serviceName(repoID: repoID, storage: .iCloudKeychain),
            storage: .iCloudKeychain
        )
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw BackupError.preflightFailed(readFailureMessage(status: status, storage: .iCloudKeychain))
        }
        guard let data = item as? Data,
              let passphrase = String(data: data, encoding: .utf8) else {
            throw BackupError.preflightFailed("Stored iCloud Keychain passphrase could not be decoded")
        }
        return passphrase
    }

    private func serviceName(repoID: String, storage: PassphraseStorageMode) -> String {
        switch storage {
        case .localKeychain:
            return "borgbar-repo-\(repoID)"
        case .iCloudKeychain:
            return "borgbar-repo-\(repoID)-icloud"
        }
    }

    private func baseQuery(service: String, storage: PassphraseStorageMode) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: Self.account,
            kSecAttrService as String: service
        ]
        if storage == .iCloudKeychain {
            query[kSecUseDataProtectionKeychain as String] = true
            query[kSecAttrSynchronizable as String] = true
        }
        return query
    }

    private func ensureAvailability(for storage: PassphraseStorageMode) throws {
        let availability = availability(for: storage)
        guard availability.isAvailable else {
            throw BackupError.preflightFailed(availability.message ?? "Selected passphrase storage is unavailable")
        }
    }

    private func currentSigningEntitlements() -> KeychainSigningEntitlements {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return KeychainSigningEntitlements(
                applicationIdentifier: nil,
                teamIdentifier: nil,
                keychainAccessGroups: []
            )
        }

        return KeychainSigningEntitlements(
            applicationIdentifier: entitlementString("com.apple.application-identifier", task: task),
            teamIdentifier: entitlementString("com.apple.developer.team-identifier", task: task),
            keychainAccessGroups: entitlementStringArray("keychain-access-groups", task: task)
        )
    }

    private func entitlementString(_ key: String, task: SecTask) -> String? {
        SecTaskCopyValueForEntitlement(task, key as CFString, nil) as? String
    }

    private func entitlementStringArray(_ key: String, task: SecTask) -> [String] {
        SecTaskCopyValueForEntitlement(task, key as CFString, nil) as? [String] ?? []
    }

    private func saveFailureMessage(status: OSStatus, storage: PassphraseStorageMode) -> String {
        switch (storage, status) {
        case (.iCloudKeychain, errSecMissingEntitlement):
            return availability(for: .iCloudKeychain).message
                ?? "Could not save passphrase to iCloud Keychain because this build is missing required entitlements"
        case (.iCloudKeychain, errSecNotAvailable):
            return "Could not save passphrase to iCloud Keychain because iCloud Keychain is unavailable"
        default:
            return "Could not save passphrase to \(storage.keychainDisplayName) (\(status))"
        }
    }

    private func readFailureMessage(status: OSStatus, storage: PassphraseStorageMode) -> String {
        switch (storage, status) {
        case (_, errSecItemNotFound):
            return "No passphrase stored in \(storage.keychainDisplayName)"
        case (.iCloudKeychain, errSecMissingEntitlement):
            return availability(for: .iCloudKeychain).message
                ?? "Could not read passphrase from iCloud Keychain because this build is missing required entitlements"
        case (.iCloudKeychain, errSecNotAvailable):
            return "iCloud Keychain is unavailable"
        default:
            return "Could not read passphrase from \(storage.keychainDisplayName) (\(status))"
        }
    }
}

extension KeychainService {
    static func availability(
        for storage: PassphraseStorageMode,
        entitlements: KeychainSigningEntitlements
    ) -> PassphraseStorageAvailability {
        switch storage {
        case .localKeychain:
            return .available
        case .iCloudKeychain:
            guard let applicationIdentifier = entitlements.applicationIdentifier,
                  !applicationIdentifier.isEmpty,
                  let teamIdentifier = entitlements.teamIdentifier,
                  !teamIdentifier.isEmpty else {
                return .unavailable(
                    "iCloud Keychain requires a team-signed BorgBar build with keychain entitlements. This installed copy is ad hoc signed."
                )
            }
            guard !entitlements.keychainAccessGroups.isEmpty else {
                return .unavailable(
                    "iCloud Keychain requires the Keychain Access Groups entitlement. Rebuild BorgBar with a real Apple signing identity so the app can access \(applicationIdentifier)."
                )
            }
            return .available
        }
    }
}
