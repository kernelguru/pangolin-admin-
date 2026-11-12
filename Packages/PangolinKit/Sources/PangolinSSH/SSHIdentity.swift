import Crypto
import Foundation
import NIOCore
import NIOSSH
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Errors around SSH keys and certificates.
public enum SSHKeyError: Error, Equatable, Sendable, LocalizedError {
    case secureEnclaveUnavailable
    case unsupportedKeyType(String)
    case encryptedKey
    case invalidKey(String)
    case invalidCertificate(String)
    case certificateDoesNotMatchKey
    case notAUserCertificate

    public var errorDescription: String? {
        switch self {
        case .secureEnclaveUnavailable:
            "Die Secure Enclave ist auf diesem Gerät nicht verfügbar."
        case .unsupportedKeyType(let type):
            "Schlüsseltyp „\(type)“ wird nicht unterstützt. Möglich sind ed25519 und ECDSA (nistp256/384/521)."
        case .encryptedKey:
            "Der Schlüssel ist mit einer Passphrase verschlüsselt. Bitte eine unverschlüsselte Kopie importieren (ssh-keygen -p -N \"\" -f kopie) – in der App liegt er geschützt in der Keychain."
        case .invalidKey(let detail):
            "Der private Schlüssel konnte nicht gelesen werden: \(detail)"
        case .invalidCertificate(let detail):
            "Das Zertifikat konnte nicht gelesen werden: \(detail)"
        case .certificateDoesNotMatchKey:
            "Das Zertifikat wurde für einen anderen Schlüssel ausgestellt."
        case .notAUserCertificate:
            "Das ist ein Host-Zertifikat. Benötigt wird ein Benutzer-Zertifikat (ssh-keygen -s … ohne -h)."
        }
    }
}

/// Supported private key kinds.
public enum SSHKeyAlgorithm: String, Codable, Sendable, CaseIterable {
    /// P-256 key generated inside the Secure Enclave; never leaves the device.
    case secureEnclaveP256
    case ed25519
    case p256
    case p384
    case p521

    public var displayName: String {
        switch self {
        case .secureEnclaveP256: "ECDSA P-256 (Secure Enclave)"
        case .ed25519: "ed25519"
        case .p256: "ECDSA P-256"
        case .p384: "ECDSA P-384"
        case .p521: "ECDSA P-521"
        }
    }
}

/// A private key plus an optional OpenSSH user certificate signed by the user's CA.
public struct SSHIdentity: Sendable, Equatable {
    public let algorithm: SSHKeyAlgorithm
    /// Raw key material (`rawRepresentation`) or, for Secure Enclave keys, the encrypted
    /// `dataRepresentation` blob that only this device's Secure Enclave can use.
    let keyData: Data
    /// OpenSSH certificate line (`…-cert-v01@openssh.com AAAA… comment`), optional.
    public private(set) var certificate: String?

    init(algorithm: SSHKeyAlgorithm, keyData: Data, certificate: String? = nil) {
        self.algorithm = algorithm
        self.keyData = keyData
        self.certificate = certificate
    }

    // MARK: Creating

    /// Generates a new key. Prefers the Secure Enclave when available.
    public static func generate(useSecureEnclave: Bool = true) throws -> SSHIdentity {
        #if canImport(CryptoKit) && !os(Linux)
        if useSecureEnclave {
            guard SecureEnclave.isAvailable else { throw SSHKeyError.secureEnclaveUnavailable }
            let key = try SecureEnclave.P256.Signing.PrivateKey()
            return SSHIdentity(algorithm: .secureEnclaveP256, keyData: key.dataRepresentation)
        }
        #endif
        return SSHIdentity(algorithm: .ed25519, keyData: Curve25519.Signing.PrivateKey().rawRepresentation)
    }

    /// Imports an unencrypted OpenSSH private key (`-----BEGIN OPENSSH PRIVATE KEY-----`).
    public static func importOpenSSH(_ text: String) throws -> SSHIdentity {
        try OpenSSHPrivateKeyParser.parse(text)
    }

    /// Attaches a user certificate after checking that it belongs to this key.
    public func withCertificate(_ line: String?) throws -> SSHIdentity {
        guard let line = line?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else {
            return SSHIdentity(algorithm: algorithm, keyData: keyData, certificate: nil)
        }
        let info = try SSHCertificateInfo(line)
        guard info.type == .user else { throw SSHKeyError.notAUserCertificate }
        guard info.keyFingerprint == (try publicKeyFingerprint()) else { throw SSHKeyError.certificateDoesNotMatchKey }
        return SSHIdentity(algorithm: algorithm, keyData: keyData, certificate: line)
    }

    // MARK: Persistence

    /// Compact string for storing in the Keychain: `<algorithm>:<base64>`.
    public var serialized: String { "\(algorithm.rawValue):\(keyData.base64EncodedString())" }

    public init(serialized: String, certificate: String?) throws {
        let parts = serialized.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let algorithm = SSHKeyAlgorithm(rawValue: parts[0]),
              let data = Data(base64Encoded: parts[1]) else {
            throw SSHKeyError.invalidKey("Gespeicherter Schlüssel ist beschädigt.")
        }
        self.init(algorithm: algorithm, keyData: data, certificate: certificate)
    }

    // MARK: Keys

    func makePrivateKey() throws -> NIOSSHPrivateKey {
        do {
            switch algorithm {
            case .secureEnclaveP256:
                #if canImport(CryptoKit) && !os(Linux)
                return NIOSSHPrivateKey(secureEnclaveP256Key: try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: keyData))
                #else
                throw SSHKeyError.secureEnclaveUnavailable
                #endif
            case .ed25519:
                return NIOSSHPrivateKey(ed25519Key: try Curve25519.Signing.PrivateKey(rawRepresentation: keyData))
            case .p256:
                return NIOSSHPrivateKey(p256Key: try P256.Signing.PrivateKey(rawRepresentation: keyData))
            case .p384:
                return NIOSSHPrivateKey(p384Key: try P384.Signing.PrivateKey(rawRepresentation: keyData))
            case .p521:
                return NIOSSHPrivateKey(p521Key: try P521.Signing.PrivateKey(rawRepresentation: keyData))
            }
        } catch let error as SSHKeyError {
            throw error
        } catch {
            throw SSHKeyError.invalidKey(String(describing: error))
        }
    }

    /// `ecdsa-sha2-nistp256 AAAA… comment` – to be signed by the CA or put in authorized_keys.
    public func publicKeyLine(comment: String = "pangolin-admin") throws -> String {
        let key = try makePrivateKey().publicKey
        return String(openSSHPublicKey: key) + " " + comment
    }

    /// `SHA256:…` fingerprint of the public key (as shown by `ssh-keygen -lf`).
    public func publicKeyFingerprint() throws -> String {
        try SSHFingerprint.sha256(of: makePrivateKey().publicKey)
    }

    func certifiedKey() throws -> NIOSSHCertifiedPublicKey? {
        guard let certificate else { return nil }
        let key: NIOSSHPublicKey
        do {
            key = try NIOSSHPublicKey(openSSHPublicKey: certificate)
        } catch {
            throw SSHKeyError.invalidCertificate(String(describing: error))
        }
        guard let certified = NIOSSHCertifiedPublicKey(key) else {
            throw SSHKeyError.invalidCertificate("Kein Zertifikat (…-cert-v01@openssh.com erwartet).")
        }
        return certified
    }
}

/// Human-readable details of an OpenSSH certificate.
public struct SSHCertificateInfo: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case user, host }

    public let type: Kind
    public let keyID: String
    public let principals: [String]
    public let validAfter: Date?
    public let validBefore: Date?
    public let serial: UInt64
    /// Fingerprint of the certified (user) key.
    public let keyFingerprint: String
    /// Fingerprint of the CA that signed the certificate.
    public let caFingerprint: String

    public init(_ line: String) throws {
        let key: NIOSSHPublicKey
        do {
            key = try NIOSSHPublicKey(openSSHPublicKey: line.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            throw SSHKeyError.invalidCertificate(String(describing: error))
        }
        guard let cert = NIOSSHCertifiedPublicKey(key) else {
            throw SSHKeyError.invalidCertificate("Kein Zertifikat (…-cert-v01@openssh.com erwartet).")
        }
        type = cert.type == .host ? .host : .user
        keyID = cert.keyID
        principals = cert.validPrincipals
        serial = cert.serial
        validAfter = cert.validAfter == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(cert.validAfter))
        validBefore = cert.validBefore == .max ? nil : Date(timeIntervalSince1970: TimeInterval(cert.validBefore))
        keyFingerprint = try SSHFingerprint.sha256(of: cert.key)
        caFingerprint = try SSHFingerprint.sha256(of: cert.signatureKey)
    }

    /// `true` if the certificate is currently valid (time window only).
    public func isValid(at date: Date = Date()) -> Bool {
        if let validAfter, date < validAfter { return false }
        if let validBefore, date >= validBefore { return false }
        return true
    }
}

enum SSHFingerprint {
    /// OpenSSH-style `SHA256:<base64 without padding>` of the public key blob.
    static func sha256(of key: NIOSSHPublicKey) throws -> String {
        let line = String(openSSHPublicKey: key)
        let parts = line.split(separator: " ")
        guard parts.count >= 2, let blob = Data(base64Encoded: String(parts[1])) else {
            throw SSHKeyError.invalidKey("Öffentlicher Schlüssel nicht lesbar.")
        }
        let digest = Data(SHA256.hash(data: blob))
        var b64 = digest.base64EncodedString()
        while b64.hasSuffix("=") { b64.removeLast() }
        return "SHA256:" + b64
    }
}
