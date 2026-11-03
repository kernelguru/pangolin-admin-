import Foundation

// MARK: - Creating resources

/// Mode of a public resource.
public enum ResourceMode: String, Sendable, CaseIterable, Codable {
    case http, tcp, udp, ssh, rdp, vnc

    /// Raw TCP/UDP resources are exposed on a port instead of a domain.
    public var isRaw: Bool { self == .tcp || self == .udp }
}

/// Body for `PUT /org/{orgId}/public-resource`.
///
/// Pangolin accepts two shapes: HTTP-style resources (domain + subdomain) and raw TCP/UDP
/// resources (proxy port; requires `flags.allow_raw_resources` on the server).
public struct CreateResourceBody: Encodable, Sendable, Equatable {
    public var name: String
    public var mode: ResourceMode
    /// HTTP resources: the domain from `GET /org/{orgId}/domains`.
    public var domainId: String?
    /// HTTP resources: e.g. `grafana` → `grafana.example.com`. `nil` uses the base domain.
    public var subdomain: String?
    public var stickySession: Bool?
    /// Raw resources only.
    public var proxyPort: Int?

    public static func http(name: String, domainId: String, subdomain: String?,
                            mode: ResourceMode = .http) -> CreateResourceBody {
        CreateResourceBody(name: name, mode: mode, domainId: domainId,
                           subdomain: subdomain?.isEmpty == true ? nil : subdomain)
    }

    public static func raw(name: String, mode: ResourceMode, proxyPort: Int) -> CreateResourceBody {
        CreateResourceBody(name: name, mode: mode, proxyPort: proxyPort)
    }

    public init(name: String, mode: ResourceMode, domainId: String? = nil, subdomain: String? = nil,
                stickySession: Bool? = nil, proxyPort: Int? = nil) {
        self.name = name
        self.mode = mode
        self.domainId = domainId
        self.subdomain = subdomain
        self.stickySession = stickySession
        self.proxyPort = proxyPort
    }

    enum CodingKeys: String, CodingKey { case name, mode, domainId, subdomain, stickySession, proxyPort }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(mode, forKey: .mode)
        if mode.isRaw {
            // The raw schema is strict: only name, mode and proxyPort are allowed.
            try c.encodeIfPresent(proxyPort, forKey: .proxyPort)
        } else {
            try c.encodeIfPresent(domainId, forKey: .domainId)
            try c.encodeIfPresent(subdomain, forKey: .subdomain)
            try c.encodeIfPresent(stickySession, forKey: .stickySession)
        }
    }
}

// MARK: - Authentication

/// Body for `POST /public-resource/{id}/password`. `nil` removes the password.
public struct SetPasswordBody: Encodable, Sendable {
    /// 4…100 characters, or `nil` to remove.
    public var password: String?
    public init(password: String?) { self.password = password }

    enum CodingKeys: String, CodingKey { case password }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(password, forKey: .password) // explicit null
    }
}

/// Body for `POST /public-resource/{id}/pincode`. `nil` removes the PIN.
public struct SetPincodeBody: Encodable, Sendable {
    /// Exactly 6 digits, or `nil` to remove.
    public var pincode: String?
    public init(pincode: String?) { self.pincode = pincode }

    enum CodingKeys: String, CodingKey { case pincode }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pincode, forKey: .pincode)
    }
}

/// Body for `POST /public-resource/{id}/header-auth`. All `nil` removes header auth.
public struct SetHeaderAuthBody: Encodable, Sendable {
    public var user: String?
    public var password: String?
    public var extendedCompatibility: Bool?

    public init(user: String?, password: String?, extendedCompatibility: Bool? = nil) {
        self.user = user
        self.password = password
        self.extendedCompatibility = extendedCompatibility
    }

    public static let remove = SetHeaderAuthBody(user: nil, password: nil, extendedCompatibility: nil)

    enum CodingKeys: String, CodingKey { case user, password, extendedCompatibility }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(user, forKey: .user)
        try c.encode(password, forKey: .password)
        try c.encode(extendedCompatibility, forKey: .extendedCompatibility)
    }
}

public enum PangolinValidation {
    /// Pangolin requires passwords of 4…100 characters.
    public static func isValidPassword(_ value: String) -> Bool {
        (4...100).contains(value.count)
    }

    /// Pangolin PINs are exactly six digits.
    public static func isValidPincode(_ value: String) -> Bool {
        value.count == 6 && value.allSatisfy(\.isASCII) && value.allSatisfy(\.isNumber)
    }
}

// MARK: - Rules

public enum RuleAction: String, Sendable, CaseIterable, Codable {
    /// Allow without authentication.
    case accept = "ACCEPT"
    /// Block the request.
    case drop = "DROP"
    /// Continue with normal authentication.
    case pass = "PASS"
}

public enum RuleMatch: String, Sendable, CaseIterable, Codable {
    case cidr = "CIDR"
    case ip = "IP"
    case path = "PATH"
    case country = "COUNTRY"
    case countryIsNot = "COUNTRY_IS_NOT"
    case asn = "ASN"
    case region = "REGION"
    case method = "METHOD"
}

/// A resource rule (`GET /public-resource/{id}/rules`). Rules are evaluated by ascending priority.
public struct ResourceRule: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { ruleId }
    public var ruleId: Int
    public var resourceId: Int?
    public var action: RuleAction?
    /// Raw action string, kept when Pangolin adds a new action.
    public var actionRaw: String
    public var match: RuleMatch?
    public var matchRaw: String
    public var value: String
    public var priority: Int
    public var enabled: Bool

    enum CodingKeys: String, CodingKey { case ruleId, resourceId, action, match, value, priority, enabled }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ruleId = c.lenientInt(.ruleId) ?? 0
        resourceId = c.lenientInt(.resourceId)
        actionRaw = c.lenientString(.action) ?? ""
        action = RuleAction(rawValue: actionRaw)
        matchRaw = c.lenientString(.match) ?? ""
        match = RuleMatch(rawValue: matchRaw)
        value = c.lenientString(.value) ?? ""
        priority = c.lenientInt(.priority) ?? 0
        enabled = c.lenientBool(.enabled) ?? true
    }
}

/// Body for `PUT /public-resource/{id}/rule` and `POST /public-resource/{id}/rule/{ruleId}`.
public struct RuleBody: Encodable, Sendable, Equatable {
    public var action: RuleAction
    public var match: RuleMatch
    public var value: String
    public var priority: Int
    public var enabled: Bool

    public init(action: RuleAction, match: RuleMatch, value: String, priority: Int, enabled: Bool = true) {
        self.action = action
        self.match = match
        self.value = value
        self.priority = priority
        self.enabled = enabled
    }
}
