import Foundation

/// A saved Pangolin server. Non-secret settings live in UserDefaults;
/// the API key is stored separately in the Keychain under `id.uuidString`.
struct ServerProfile: Codable, Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    /// Integration API URL, e.g. `https://api.example.com/v1`.
    var baseURL: String
    /// Organization to manage. Required for org-scoped keys; optional for root keys.
    var orgId: String?
    /// Root keys (Server Admin → API Keys) can list and switch between all organizations.
    var isRootKey: Bool = false
    /// SSH access to the Docker host for server updates (optional). The private key lives in the Keychain.
    var ssh: SSHSettings?

    var keychainAccount: String { id.uuidString }
    var sshKeychainAccount: String { id.uuidString + ".ssh-key" }

    var url: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }

    var host: String { url?.host ?? baseURL }
}

/// SSH connection settings of a profile (no secrets).
struct SSHSettings: Codable, Hashable, Sendable {
    var host: String
    var port: Int = 22
    var username: String
    /// Pinned `SHA256:…` host key fingerprint, confirmed by the user on first connect.
    var hostKeyFingerprint: String?
    /// OpenSSH user certificate signed by the user's CA (public data).
    var certificate: String?
    /// Last detached update job, so the app can re-attach after being backgrounded.
    var lastJobLog: String?
    var lastJobPID: Int?
}
