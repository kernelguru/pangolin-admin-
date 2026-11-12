import Crypto
import Foundation

/// Parses unencrypted keys in OpenSSH's `openssh-key-v1` format (ed25519 and ECDSA).
/// Format: https://github.com/openssh/openssh-portable/blob/master/PROTOCOL.key
enum OpenSSHPrivateKeyParser {
    static func parse(_ text: String) throws -> SSHIdentity {
        let body = text
            .replacingOccurrences(of: "\r", with: "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
            .joined()
        guard text.contains("BEGIN OPENSSH PRIVATE KEY") else {
            if text.contains("BEGIN") && text.contains("ENCRYPTED") { throw SSHKeyError.encryptedKey }
            throw SSHKeyError.invalidKey("Erwartet wird das OpenSSH-Format („-----BEGIN OPENSSH PRIVATE KEY-----“).")
        }
        guard let data = Data(base64Encoded: body) else {
            throw SSHKeyError.invalidKey("Base64-Inhalt ungültig.")
        }

        var reader = SSHBinaryReader(data)
        let magic = Array("openssh-key-v1".utf8) + [0]
        guard reader.readBytes(magic.count) == magic else {
            throw SSHKeyError.invalidKey("Kein openssh-key-v1.")
        }
        let cipher = try reader.readString()
        let kdf = try reader.readString()
        _ = try reader.readData() // kdf options
        guard cipher == "none", kdf == "none" else { throw SSHKeyError.encryptedKey }
        let count = try reader.readUInt32()
        guard count == 1 else { throw SSHKeyError.invalidKey("Mehr als ein Schlüssel in der Datei.") }
        _ = try reader.readData() // public key blob

        var priv = SSHBinaryReader(try reader.readData())
        let check1 = try priv.readUInt32()
        let check2 = try priv.readUInt32()
        guard check1 == check2 else { throw SSHKeyError.encryptedKey }

        let type = try priv.readString()
        switch type {
        case "ssh-ed25519":
            _ = try priv.readData() // public key (32)
            let secret = try priv.readData() // 64 bytes: seed || public
            guard secret.count == 64 else { throw SSHKeyError.invalidKey("ed25519-Schlüssel hat falsche Länge.") }
            let seed = secret.prefix(32)
            _ = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
            return SSHIdentity(algorithm: .ed25519, keyData: Data(seed))

        case "ecdsa-sha2-nistp256", "ecdsa-sha2-nistp384", "ecdsa-sha2-nistp521":
            _ = try priv.readString() // curve name
            _ = try priv.readData() // public point Q
            let scalar = try priv.readMPInt()
            let (algorithm, length): (SSHKeyAlgorithm, Int) = switch type {
            case "ecdsa-sha2-nistp256": (.p256, 32)
            case "ecdsa-sha2-nistp384": (.p384, 48)
            default: (.p521, 66)
            }
            let raw = leftPad(scalar, to: length)
            do {
                switch algorithm {
                case .p256: _ = try P256.Signing.PrivateKey(rawRepresentation: raw)
                case .p384: _ = try P384.Signing.PrivateKey(rawRepresentation: raw)
                default: _ = try P521.Signing.PrivateKey(rawRepresentation: raw)
                }
            } catch {
                throw SSHKeyError.invalidKey(String(describing: error))
            }
            return SSHIdentity(algorithm: algorithm, keyData: raw)

        default:
            throw SSHKeyError.unsupportedKeyType(type)
        }
    }

    private static func leftPad(_ data: Data, to length: Int) -> Data {
        var bytes = [UInt8](data)
        while bytes.count > length, bytes.first == 0 { bytes.removeFirst() }
        if bytes.count < length { bytes = [UInt8](repeating: 0, count: length - bytes.count) + bytes }
        return Data(bytes)
    }
}

/// Reader for SSH wire-format primitives (RFC 4251).
struct SSHBinaryReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func readBytes(_ count: Int) -> [UInt8]? {
        guard count >= 0, offset + count <= bytes.count else { return nil }
        defer { offset += count }
        return Array(bytes[offset ..< offset + count])
    }

    mutating func readUInt32() throws -> UInt32 {
        guard let b = readBytes(4) else { throw SSHKeyError.invalidKey("Datei zu kurz.") }
        return b.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    mutating func readData() throws -> Data {
        let length = Int(try readUInt32())
        guard let b = readBytes(length) else { throw SSHKeyError.invalidKey("Datei zu kurz.") }
        return Data(b)
    }

    mutating func readString() throws -> String {
        guard let string = String(data: try readData(), encoding: .utf8) else {
            throw SSHKeyError.invalidKey("Ungültiger Text.")
        }
        return string
    }

    /// Positive mpint: big-endian with an optional leading zero byte.
    mutating func readMPInt() throws -> Data {
        var data = try readData()
        while data.first == 0 { data.removeFirst() }
        return data
    }
}
