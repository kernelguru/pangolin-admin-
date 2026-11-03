import Foundation

/// A target behind a public resource (`/public-resource/{id}/targets`, `/target/{targetId}`).
public struct Target: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { targetId }
    public var targetId: Int
    public var resourceId: Int?
    public var siteId: Int?
    public var siteName: String?
    public var siteType: String?
    public var ip: String
    public var port: Int
    public var method: String?
    public var mode: String?
    public var enabled: Bool
    public var path: String?
    public var pathMatchType: String?
    public var rewritePath: String?
    public var rewritePathType: String?
    public var priority: Int?
    public var hcEnabled: Bool?
    public var hcPath: String?
    public var hcScheme: String?
    public var hcPort: Int?
    public var hcInterval: Int?
    public var hcTimeout: Int?
    /// `healthy`, `unhealthy` or `unknown`.
    public var hcHealth: String?

    /// `http://10.0.0.5:8080/path`
    public var displayAddress: String {
        let scheme = method.map { "\($0)://" } ?? ""
        return "\(scheme)\(ip):\(port)\(path ?? "")"
    }

    public init(targetId: Int, ip: String, port: Int, enabled: Bool = true, siteId: Int? = nil) {
        self.targetId = targetId
        self.ip = ip
        self.port = port
        self.enabled = enabled
        self.siteId = siteId
    }

    enum CodingKeys: String, CodingKey {
        case targetId, resourceId, siteId, siteName, siteType, ip, port, method, mode, enabled, path,
             pathMatchType, rewritePath, rewritePathType, priority, hcEnabled, hcPath, hcScheme, hcPort,
             hcInterval, hcTimeout, hcHealth
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        targetId = c.lenientInt(.targetId) ?? 0
        resourceId = c.lenientInt(.resourceId)
        siteId = c.lenientInt(.siteId)
        siteName = c.lenientString(.siteName)
        siteType = c.lenientString(.siteType)
        ip = c.lenientString(.ip) ?? ""
        port = c.lenientInt(.port) ?? 0
        method = c.lenientString(.method)
        mode = c.lenientString(.mode)
        enabled = c.lenientBool(.enabled) ?? true
        path = c.lenientString(.path)
        pathMatchType = c.lenientString(.pathMatchType)
        rewritePath = c.lenientString(.rewritePath)
        rewritePathType = c.lenientString(.rewritePathType)
        priority = c.lenientInt(.priority)
        hcEnabled = c.lenientBool(.hcEnabled)
        hcPath = c.lenientString(.hcPath)
        hcScheme = c.lenientString(.hcScheme)
        hcPort = c.lenientInt(.hcPort)
        hcInterval = c.lenientInt(.hcInterval)
        hcTimeout = c.lenientInt(.hcTimeout)
        hcHealth = c.lenientString(.hcHealth)
    }
}

/// Body for `PUT /public-resource/{resourceId}/target`.
public struct CreateTargetBody: Encodable, Sendable {
    public var siteId: Int
    public var ip: String
    public var port: Int
    /// `http`, `https`, `h2c` for HTTP resources; `nil` for TCP/UDP.
    public var method: String?
    public var enabled: Bool

    public init(siteId: Int, ip: String, port: Int, method: String? = nil, enabled: Bool = true) {
        self.siteId = siteId
        self.ip = ip
        self.port = port
        self.method = method
        self.enabled = enabled
    }
}

/// Body for `POST /target/{targetId}`. Pangolin requires `siteId` and `ip` on every update.
public struct UpdateTargetBody: Encodable, Sendable {
    public var siteId: Int
    public var ip: String
    public var port: Int?
    public var method: String?
    public var enabled: Bool?

    public init(siteId: Int, ip: String, port: Int? = nil, method: String? = nil, enabled: Bool? = nil) {
        self.siteId = siteId
        self.ip = ip
        self.port = port
        self.method = method
        self.enabled = enabled
    }

    /// Creates an update body that keeps the target as it is.
    public init(target: Target) {
        self.init(siteId: target.siteId ?? 0, ip: target.ip, port: target.port, method: target.method,
                  enabled: target.enabled)
    }
}
