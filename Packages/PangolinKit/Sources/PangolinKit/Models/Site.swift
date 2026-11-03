import Foundation

/// A site (Newt tunnel, WireGuard peer or local site).
/// Covers both `GET /org/{orgId}/sites` rows and `GET /site/{siteId}`.
public struct Site: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { siteId }
    public var siteId: Int
    public var niceId: String
    public var name: String
    public var orgId: String?
    public var orgName: String?
    /// `newt`, `wireguard` or `local`.
    public var type: String?
    /// `nil` for local sites (no tunnel).
    public var online: Bool?
    /// `pending` or `approved`.
    public var status: String?
    public var address: String?
    public var subnet: String?
    public var endpoint: String?
    public var megabytesIn: Double?
    public var megabytesOut: Double?
    public var newtVersion: String?
    public var newtUpdateAvailable: Bool?
    public var agent: String?
    public var agentVersion: String?
    public var exitNodeId: Int?
    public var exitNodeName: String?
    public var exitNodeEndpoint: String?
    public var resourceCount: Int?
    public var dockerSocketEnabled: Bool?
    public var autoUpdateEnabled: Bool?
    public var countryCode: String?
    public var lastPing: Int?
    public var labels: [PangolinLabel]

    public var isLocal: Bool { type == "local" }
    public var isPending: Bool { status == "pending" }
    public var totalMegabytes: Double { (megabytesIn ?? 0) + (megabytesOut ?? 0) }

    public init(siteId: Int, niceId: String, name: String, type: String? = nil, online: Bool? = nil,
                status: String? = nil, megabytesIn: Double? = nil, megabytesOut: Double? = nil) {
        self.siteId = siteId
        self.niceId = niceId
        self.name = name
        self.type = type
        self.online = online
        self.status = status
        self.megabytesIn = megabytesIn
        self.megabytesOut = megabytesOut
        self.labels = []
    }

    enum CodingKeys: String, CodingKey {
        case siteId, niceId, name, orgId, orgName, type, online, status, address, subnet, exitNodeSubnet,
             endpoint, megabytesIn, megabytesOut, newtVersion, newtUpdateAvailable, agent, agentVersion,
             exitNodeId, exitNodeName, exitNodeEndpoint, resourceCount, dockerSocketEnabled,
             autoUpdateEnabled, countryCode, lastPing, labels
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let siteId = c.lenientInt(.siteId) else {
            throw DecodingError.keyNotFound(CodingKeys.siteId, .init(codingPath: c.codingPath, debugDescription: "siteId"))
        }
        self.siteId = siteId
        niceId = c.lenientString(.niceId) ?? String(siteId)
        name = c.lenientString(.name) ?? niceId
        orgId = c.lenientString(.orgId)
        orgName = c.lenientString(.orgName)
        type = c.lenientString(.type)
        online = c.lenientBool(.online)
        status = c.lenientString(.status)
        address = c.lenientString(.address)
        subnet = c.lenientString(.subnet) ?? c.lenientString(.exitNodeSubnet)
        endpoint = c.lenientString(.endpoint)
        megabytesIn = c.lenientDouble(.megabytesIn)
        megabytesOut = c.lenientDouble(.megabytesOut)
        newtVersion = c.lenientString(.newtVersion)
        newtUpdateAvailable = c.lenientBool(.newtUpdateAvailable)
        agent = c.lenientString(.agent)
        agentVersion = c.lenientString(.agentVersion)
        exitNodeId = c.lenientInt(.exitNodeId)
        exitNodeName = c.lenientString(.exitNodeName)
        exitNodeEndpoint = c.lenientString(.exitNodeEndpoint)
        resourceCount = c.lenientInt(.resourceCount)
        dockerSocketEnabled = c.lenientBool(.dockerSocketEnabled)
        autoUpdateEnabled = c.lenientBool(.autoUpdateEnabled)
        countryCode = c.lenientString(.countryCode)
        lastPing = c.lenientInt(.lastPing)
        labels = c.lenientArray(PangolinLabel.self, .labels)
    }
}

/// Body for `POST /site/{siteId}`.
public struct UpdateSiteBody: Encodable, Sendable {
    public var name: String?
    public var niceId: String?
    public var dockerSocketEnabled: Bool?
    public var autoUpdateEnabled: Bool?
    public var autoUpdateOverrideOrg: Bool?

    public init(name: String? = nil, niceId: String? = nil, dockerSocketEnabled: Bool? = nil,
                autoUpdateEnabled: Bool? = nil, autoUpdateOverrideOrg: Bool? = nil) {
        self.name = name
        self.niceId = niceId
        self.dockerSocketEnabled = dockerSocketEnabled
        self.autoUpdateEnabled = autoUpdateEnabled
        self.autoUpdateOverrideOrg = autoUpdateOverrideOrg
    }
}

/// Filters for `GET /org/{orgId}/sites`.
public struct SiteQuery: Sendable, Equatable {
    public enum SortField: String, Sendable { case name, megabytesIn, megabytesOut }

    public var search: String?
    public var online: Bool?
    /// `pending` or `approved`.
    public var status: String?
    public var sortBy: SortField?
    public var order: SortOrder?

    public init(search: String? = nil, online: Bool? = nil, status: String? = nil,
                sortBy: SortField? = nil, order: SortOrder? = nil) {
        self.search = search
        self.online = online
        self.status = status
        self.sortBy = sortBy
        self.order = order
    }
}

/// A label attached to sites, resources or clients.
public struct PangolinLabel: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { labelId }
    public var labelId: Int
    public var name: String
    public var color: String?

    enum CodingKeys: String, CodingKey { case labelId, name, color }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        labelId = c.lenientInt(.labelId) ?? 0
        name = c.lenientString(.name) ?? ""
        color = c.lenientString(.color)
    }
}
