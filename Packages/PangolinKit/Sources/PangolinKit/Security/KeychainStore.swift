import Foundation

/// Abstraction over secret storage so the app can be tested without a real Keychain.
public protocol SecretStore: Sendable {
    func save(_ secret: String, for account: String) throws
    func read(_ account: String) throws -> String?
    func delete(_ account: String) throws
}

public enum KeychainError: Error, Sendable, Equatable, LocalizedError {
    case unexpectedStatus(Int32)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status): "Keychain-Fehler (OSStatus \(status))"
        case .invalidData: "Keychain-Eintrag ist beschädigt"
        }
    }
}

/// In-memory store for previews and tests.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    public init(_ initial: [String: String] = [:]) { storage = initial }

    public func save(_ secret: String, for account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[account] = secret
    }

    public func read(_ account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[account]
    }

    public func delete(_ account: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[account] = nil
    }
}

#if canImport(Security)
import Security

/// Stores API keys as generic passwords in the iOS Keychain.
///
/// - Items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: they are only readable
///   while the device is unlocked, are never synced to iCloud and are not part of
///   device-to-device backups.
/// - One item per server profile; the profile's UUID is the account name.
public struct KeychainStore: SecretStore {
    public let service: String

    public init(service: String = "pangolin-admin.api-keys") {
        self.service = service
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public func save(_ secret: String, for account: String) throws {
        let data = Data(secret.utf8)
        var query = baseQuery(account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            query.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    public func read(_ account: String) throws -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidData
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func delete(_ account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
#endif
