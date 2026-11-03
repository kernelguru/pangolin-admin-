import Foundation

/// Aggregated health of a resource's targets.
public enum ResourceHealth: String, Sendable, Hashable, CaseIterable {
    case healthy, degraded, offline, unhealthy, unknown
}

/// A public resource (reverse-proxied HTTP/TCP/UDP service).
/// Covers `GET /org/{orgId}/public-resources` rows and `GET /public-resource/{resourceId}`.
public struct PublicResource: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { resourceId }
    public var resourceId: Int
    public var niceId: String
    public var name: String
    public var orgId: String?
    public var fullDomain: String?
    public var subdomain: String?
    public var domainId: String?
    public var ssl: Bool?
    public var enabled: Bool
    public var sso: Bool?
    public var whitelist: Bool?
    public var mtls: Bool?
    public var blockAccess: Bool?
    public var applyRules: Bool?
    public var stickySession: Bool?
    public var wildcard: Bool?
    public var http: Bool?
    public var proxyPort: Int?
    /// `http`, `tcp`, `udp`, `ssh`, …
    public var mode: String?
    public var protocolName: String?
    public var health: ResourceHealth?
    public var passwordId: Int?
    public var pincodeId: Int?
    public var headerAuthId: Int?
    public var loadBalancingStrategy: String?
    public var targets: [TargetSummary]
    public var sites: [ResourceSite]
    public var labels: [PangolinLabel]

    /// `true` when at least one authentication mechanism protects the resource.
    public var isProtected: Bool {
        (sso ?? false) || (whitelist ?? false) || (mtls ?? false)
            || passwordId != nil || pincodeId != nil || headerAuthId != nil
    }

    /// Human-readable address (`https://app.example.com` or `:2222`).
    public var displayAddress: String {
        if let fullDomain, !fullDomain.isEmpty {
            return ((ssl ?? true) ? "https://" : "http://") + fullDomain
        }
        if let proxyPort { return "\(protocolName ?? mode ?? "tcp"):\(proxyPort)" }
        return niceId
    }

    public init(resourceId: Int, niceId: String, name: String, enabled: Bool = true,
                fullDomain: String? = nil, health: ResourceHealth? = nil) {
        self.resourceId = resourceId
        self.niceId = niceId
        self.name = name
        self.enabled = enabled
        self.fullDomain = fullDomain
        self.health = health
        self.targets = []
        self.sites = []
        self.labels = []
    }

    enum CodingKeys: String, CodingKey {
        case resourceId, niceId, name, orgId, fullDomain, subdomain, domainId, ssl, enabled, sso, whitelist,
             emailWhitelistEnabled, mtls, blockAccess, applyRules, stickySession, wildcard, http, proxyPort,
             mode, `protocol`, health, passwordId, pincodeId, headerAuthId, loadBalancingStrategy,
             targets, sites, labels
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let resourceId = c.lenientInt(.resourceId) else {
            throw DecodingError.keyNotFound(CodingKeys.resourceId, .init(codingPath: c.codingPath, debugDescription: "resourceId"))
        }
        self.resourceId = resourceId
        niceId = c.lenientString(.niceId) ?? String(resourceId)
        name = c.lenientString(.name) ?? niceId
        orgId = c.lenientString(.orgId)
        fullDomain = c.lenientString(.fullDomain)
        subdomain = c.lenientString(.subdomain)
        domainId = c.lenientString(.domainId)
        ssl = c.lenientBool(.ssl)
        enabled = c.lenientBool(.enabled) ?? true
        sso = c.lenientBool(.sso)
        whitelist = c.lenientBool(.whitelist) ?? c.lenientBool(.emailWhitelistEnabled)
        mtls = c.lenientBool(.mtls)
        blockAccess = c.lenientBool(.blockAccess)
        applyRules = c.lenientBool(.applyRules)
        stickySession = c.lenientBool(.stickySession)
        wildcard = c.lenientBool(.wildcard)
        http = c.lenientBool(.http)
        proxyPort = c.lenientInt(.proxyPort)
        mode = c.lenientString(.mode)
        protocolName = c.lenientString(.protocol)
        health = c.lenientString(.health).flatMap(ResourceHealth.init(rawValue:))
        passwordId = c.lenientInt(.passwordId)
        pincodeId = c.lenientInt(.pincodeId)
        headerAuthId = c.lenientInt(.headerAuthId)
        loadBalancingStrategy = c.lenientString(.loadBalancingStrategy)
        targets = c.lenientArray(TargetSummary.self, .targets)
        sites = c.lenientArray(ResourceSite.self, .sites)
        labels = c.lenientArray(PangolinLabel.self, .labels)
    }
}

/// Short target info embedded in resource lists.
public struct TargetSummary: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { targetId }
    public var targetId: Int
    public var ip: String
    public var port: Int?
    public var enabled: Bool?
    /// `healthy`, `unhealthy`, `unknown` or `nil`.
    public var healthStatus: String?
    public var siteName: String?

    enum CodingKeys: String, CodingKey { case targetId, ip, port, enabled, healthStatus, siteName }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        targetId = c.lenientInt(.targetId) ?? 0
        ip = c.lenientString(.ip) ?? ""
        port = c.lenientInt(.port)
        enabled = c.lenientBool(.enabled)
        healthStatus = c.lenientString(.healthStatus)
        siteName = c.lenientString(.siteName)
    }
}

/// Site reference embedded in resource lists.
public struct ResourceSite: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { siteId }
    public var siteId: Int
    public var siteName: String
    public var siteNiceId: String?
    public var online: Bool?

    enum CodingKeys: String, CodingKey { case siteId, siteName, siteNiceId, online }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        siteId = c.lenientInt(.siteId) ?? 0
        siteName = c.lenientString(.siteName) ?? ""
        siteNiceId = c.lenientString(.siteNiceId)
        online = c.lenientBool(.online)
    }
}

/// Filters for `GET /org/{orgId}/public-resources`.
public struct ResourceQuery: Sendable, Equatable {
    public enum AuthState: String, Sendable { case protected, notProtected = "not_protected", none }
    public enum HealthFilter: String, Sendable { case healthy, degraded, offline, unknown }

    public var search: String?
    public var enabled: Bool?
    public var authState: AuthState?
    public var health: HealthFilter?
    public var order: SortOrder?

    public init(search: String? = nil, enabled: Bool? = nil, authState: AuthState? = nil,
                health: HealthFilter? = nil, order: SortOrder? = nil) {
        self.search = search
        self.enabled = enabled
        self.authState = authState
        self.health = health
        self.order = order
    }
}

/// Body for `POST /public-resource/{resourceId}`. Only non-nil fields are sent.
public struct UpdateResourceBody: Encodable, Sendable {
    public var name: String?
    public var enabled: Bool?
    public var sso: Bool?
    public var blockAccess: Bool?
    public var emailWhitelistEnabled: Bool?
    public var applyRules: Bool?
    public var ssl: Bool?
    public var stickySession: Bool?

    public init(name: String? = nil, enabled: Bool? = nil, sso: Bool? = nil, blockAccess: Bool? = nil,
                emailWhitelistEnabled: Bool? = nil, applyRules: Bool? = nil, ssl: Bool? = nil,
                stickySession: Bool? = nil) {
        self.name = name
        self.enabled = enabled
        self.sso = sso
        self.blockAccess = blockAccess
        self.emailWhitelistEnabled = emailWhitelistEnabled
        self.applyRules = applyRules
        self.ssl = ssl
        self.stickySession = stickySession
    }
}
