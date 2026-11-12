import Foundation
import Observation
import PangolinKit

/// Everything a screen needs to talk to the selected organization.
struct OrgContext: Hashable {
    let client: PangolinClient
    let orgId: String
    let profileID: UUID

    static func == (lhs: OrgContext, rhs: OrgContext) -> Bool {
        lhs.orgId == rhs.orgId && lhs.profileID == rhs.profileID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(orgId)
        hasher.combine(profileID)
    }
}

/// App-wide state: saved servers, the active connection and the selected organization.
@MainActor
@Observable
final class AppModel {
    private(set) var profiles: [ServerProfile] = []
    private(set) var activeProfileID: UUID?
    private(set) var organizations: [Organization] = []
    var selectedOrgId: String? {
        didSet { persistSelection() }
    }
    private(set) var client: PangolinClient?
    private(set) var connectionError: String?
    private(set) var isConnecting = false

    private let secrets: SecretStore
    private let defaults: UserDefaults

    private enum Keys {
        static let profiles = "profiles.v1"
        static let activeProfile = "profiles.active"
        static let selectedOrg = "profiles.selectedOrg"
    }

    init(secrets: SecretStore, defaults: UserDefaults = .standard) {
        self.secrets = secrets
        self.defaults = defaults
        loadProfiles()
    }

    convenience init() {
        self.init(secrets: KeychainStore())
    }

    // MARK: Derived state

    var activeProfile: ServerProfile? {
        profiles.first { $0.id == activeProfileID }
    }

    var context: OrgContext? {
        guard let client, let orgId = selectedOrgId, let profileID = activeProfileID else { return nil }
        return OrgContext(client: client, orgId: orgId, profileID: profileID)
    }

    var selectedOrganization: Organization? {
        organizations.first { $0.orgId == selectedOrgId }
    }

    // MARK: Profiles

    /// Tests a configuration without saving it. Returns the reachable organizations.
    func test(baseURL: URL, apiKey: String, orgId: String?) async throws -> [Organization] {
        let client = PangolinClient(configuration: PangolinConfiguration(baseURL: baseURL, apiKey: apiKey))
        return try await client.verifyAccess(orgId: orgId)
    }

    /// Saves a profile and its API key (Keychain). Pass `apiKey: nil` to keep the stored key.
    func save(_ profile: ServerProfile, apiKey: String?) throws {
        if let apiKey {
            let cleaned = PangolinConfiguration.sanitize(apiKey: apiKey)
            if !cleaned.isEmpty { try secrets.save(cleaned, for: profile.keychainAccount) }
        }
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        persistProfiles()
    }

    func delete(_ profile: ServerProfile) {
        try? secrets.delete(profile.keychainAccount)
        try? secrets.delete(profile.sshKeychainAccount)
        profiles.removeAll { $0.id == profile.id }
        persistProfiles()
        if activeProfileID == profile.id {
            disconnect()
            if let next = profiles.first {
                Task { await connect(to: next) }
            }
        }
    }

    func hasStoredKey(for profile: ServerProfile) -> Bool {
        storedAPIKey(for: profile) != nil
    }

    func storedAPIKey(for profile: ServerProfile) -> String? {
        (try? secrets.read(profile.keychainAccount)) ?? nil
    }

    // MARK: SSH

    /// The SSH private key (serialized) of a profile, from the Keychain.
    func sshKey(for profile: ServerProfile) -> String? {
        (try? secrets.read(profile.sshKeychainAccount)) ?? nil
    }

    func saveSSHKey(_ serialized: String?, for profile: ServerProfile) throws {
        if let serialized {
            try secrets.save(serialized, for: profile.sshKeychainAccount)
        } else {
            try secrets.delete(profile.sshKeychainAccount)
        }
    }

    /// Updates only the SSH settings of a profile.
    func updateSSH(_ settings: SSHSettings?, for profileID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].ssh = settings
        persistProfiles()
    }

    // MARK: Connection

    /// Restores the last active profile on launch.
    func restore() async {
        guard client == nil else { return }
        let lastID = defaults.string(forKey: Keys.activeProfile).flatMap(UUID.init(uuidString:))
        if let profile = profiles.first(where: { $0.id == lastID }) ?? profiles.first {
            await connect(to: profile)
        }
    }

    func connect(to profile: ServerProfile) async {
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }

        guard let url = profile.url else {
            connectionError = "Die Server-URL ist ungültig."
            return
        }
        let apiKey: String
        do {
            guard let stored = try secrets.read(profile.keychainAccount) else {
                connectionError = "Für diesen Server ist kein API-Schlüssel gespeichert."
                return
            }
            apiKey = stored
        } catch {
            connectionError = error.localizedDescription
            return
        }

        let client = PangolinClient(configuration: PangolinConfiguration(baseURL: url, apiKey: apiKey))
        self.client = client
        activeProfileID = profile.id
        defaults.set(profile.id.uuidString, forKey: Keys.activeProfile)

        let savedOrg = defaults.string(forKey: Keys.selectedOrg + "." + profile.id.uuidString)
        selectedOrgId = savedOrg ?? profile.orgId
        await refreshOrganizations()
    }

    func refreshOrganizations() async {
        guard let client, let profile = activeProfile else { return }
        do {
            if profile.isRootKey {
                organizations = try await client.organizations().items
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            } else if let orgId = profile.orgId {
                organizations = [try await client.organization(orgId)]
            }
            if selectedOrgId == nil || !organizations.contains(where: { $0.orgId == selectedOrgId }) {
                selectedOrgId = profile.orgId.flatMap { id in organizations.first { $0.orgId == id }?.orgId }
                    ?? organizations.first?.orgId
            }
            connectionError = nil
        } catch {
            connectionError = error.localizedDescription
            // Keep working with the configured org even if the org lookup failed (e.g. missing permission).
            if selectedOrgId == nil { selectedOrgId = profile.orgId }
        }
    }

    func disconnect() {
        client = nil
        activeProfileID = nil
        organizations = []
        selectedOrgId = nil
    }

    // MARK: Persistence

    private func loadProfiles() {
        guard let data = defaults.data(forKey: Keys.profiles),
              let decoded = try? JSONDecoder().decode([ServerProfile].self, from: data) else { return }
        profiles = decoded
    }

    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Keys.profiles)
        }
    }

    private func persistSelection() {
        guard let activeProfileID else { return }
        defaults.set(selectedOrgId, forKey: Keys.selectedOrg + "." + activeProfileID.uuidString)
    }
}
