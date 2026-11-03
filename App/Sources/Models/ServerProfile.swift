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

    var keychainAccount: String { id.uuidString }

    var url: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }

    var host: String { url?.host ?? baseURL }
}
