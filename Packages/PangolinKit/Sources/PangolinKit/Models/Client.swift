import Foundation

/// A client (user device running Olm, or a machine client).
public struct Client: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { clientId }
    public var clientId: Int
    public var niceId: String?
    public var name: String
    public var orgId: String?
    public var type: String?
    public var online: Bool?
    public var subnet: String?
    public var megabytesIn: Double?
    public var megabytesOut: Double?
    public var olmVersion: String?
    public var agent: String?
    public var agentVersion: String?
    public var userId: String?
    public var username: String?
    public var userEmail: String?
    /// `pending`, `approved`, `denied` or `nil`.
    public var approvalState: String?
    public var archived: Bool?
    public var blocked: Bool?
    public var sites: [ClientSite]
    public var roles: [ClientRole]
    /// User devices only (`/user-devices`): device fingerprint.
    public var deviceModel: String?
    public var platform: String?
    public var osVersion: String?
    public var hostname: String?
    public var lastSeen: Date?
    public var olmUpdateAvailable: Bool?

    /// Machine clients have no associated user.
    public var isMachine: Bool { userId == nil }
    public var totalMegabytes: Double { (megabytesIn ?? 0) + (megabytesOut ?? 0) }

    public init(clientId: Int, name: String, online: Bool? = nil, blocked: Bool? = nil) {
        self.clientId = clientId
        self.name = name
        self.online = online
        self.blocked = blocked
        self.sites = []
        self.roles = []
    }

    enum CodingKeys: String, CodingKey {
        case clientId, niceId, name, orgId, type, online, subnet, megabytesIn, megabytesOut, olmVersion,
             agent, agentVersion, userId, username, userEmail, approvalState, archived, blocked, sites, roles,
             deviceModel, fingerprintPlatform, fingerprintOsVersion, fingerprintHostname, lastSeen,
             olmUpdateAvailable
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let clientId = c.lenientInt(.clientId) else {
            throw DecodingError.keyNotFound(CodingKeys.clientId, .init(codingPath: c.codingPath, debugDescription: "clientId"))
        }
        self.clientId = clientId
        niceId = c.lenientString(.niceId)
        name = c.lenientString(.name) ?? niceId ?? String(clientId)
        orgId = c.lenientString(.orgId)
        type = c.lenientString(.type)
        online = c.lenientBool(.online)
        subnet = c.lenientString(.subnet)
        megabytesIn = c.lenientDouble(.megabytesIn)
        megabytesOut = c.lenientDouble(.megabytesOut)
        olmVersion = c.lenientString(.olmVersion)
        agent = c.lenientString(.agent)
        agentVersion = c.lenientString(.agentVersion)
        userId = c.lenientString(.userId)
        username = c.lenientString(.username)
        userEmail = c.lenientString(.userEmail)
        approvalState = c.lenientString(.approvalState)
        archived = c.lenientBool(.archived)
        blocked = c.lenientBool(.blocked)
        sites = c.lenientArray(ClientSite.self, .sites)
        roles = c.lenientArray(ClientRole.self, .roles)
        deviceModel = c.lenientString(.deviceModel)
        platform = c.lenientString(.fingerprintPlatform)
        osVersion = c.lenientString(.fingerprintOsVersion)
        hostname = c.lenientString(.fingerprintHostname)
        if let value = c.lenientDouble(.lastSeen) {
            lastSeen = Date(pangolinTimestamp: value)
        } else {
            lastSeen = c.lenientString(.lastSeen).flatMap(Date.init(pangolinString:))
        }
        olmUpdateAvailable = c.lenientBool(.olmUpdateAvailable)
    }
}

public struct ClientSite: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { siteId }
    public var siteId: Int
    public var siteName: String?
    public var siteNiceId: String?

    enum CodingKeys: String, CodingKey { case siteId, siteName, siteNiceId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        siteId = c.lenientInt(.siteId) ?? 0
        siteName = c.lenientString(.siteName)
        siteNiceId = c.lenientString(.siteNiceId)
    }
}

public struct ClientRole: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { roleId }
    public var roleId: Int
    public var name: String

    enum CodingKeys: String, CodingKey { case roleId, name, roleName }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roleId = c.lenientInt(.roleId) ?? 0
        name = c.lenientString(.name) ?? c.lenientString(.roleName) ?? ""
    }
}

/// Client status filter. Pangolin only returns `active` (and `pending` for devices) unless asked.
public enum ClientStatus: String, Sendable, CaseIterable {
    case active, pending, denied, blocked, archived
}

/// Filters for `GET /org/{orgId}/clients` (machine clients) and `/user-devices`.
public struct ClientQuery: Sendable, Equatable {
    public var search: String?
    public var online: Bool?
    /// `nil` uses Pangolin's default; the `all…` helpers request every status.
    public var statuses: [ClientStatus]?

    public init(search: String? = nil, online: Bool? = nil, statuses: [ClientStatus]? = nil) {
        self.search = search
        self.online = online
        self.statuses = statuses
    }

    var statusValue: String? {
        statuses.map { $0.map(\.rawValue).joined(separator: ",") }
    }
}
