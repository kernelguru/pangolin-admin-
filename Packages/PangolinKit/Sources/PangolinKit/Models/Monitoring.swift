import Foundation

// MARK: - Health checks (Enterprise)

/// Health check mode.
public enum HealthCheckMode: String, Sendable, CaseIterable, Codable {
    case http, tcp, ping, snmp
}

/// A health check (`GET /org/{orgId}/health-checks`). Includes standalone checks and
/// checks attached to resource targets (`resourceId` set).
public struct HealthCheck: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { healthCheckId }
    public var healthCheckId: Int
    public var name: String
    public var siteId: Int?
    public var siteName: String?
    public var siteNiceId: String?
    public var enabled: Bool
    /// `healthy`, `unhealthy` or `unknown`.
    public var health: String?
    public var mode: String?
    public var hostname: String?
    public var port: Int?
    public var path: String?
    public var scheme: String?
    public var method: String?
    public var interval: Int?
    public var unhealthyInterval: Int?
    public var timeout: Int?
    public var expectedStatus: Int?
    public var followRedirects: Bool?
    public var tlsServerName: String?
    public var healthyThreshold: Int?
    public var unhealthyThreshold: Int?
    public var resourceId: Int?
    public var resourceName: String?

    /// `true` when the check belongs to a resource target rather than being standalone.
    public var isTargetCheck: Bool { resourceId != nil }

    /// `https://host:443/health`, `tcp host:22`, `ping host`.
    public var displayTarget: String {
        let host = hostname ?? "–"
        switch mode {
        case "http", nil:
            let s = scheme ?? "http"
            return "\(s)://\(host)\(port.map { ":\($0)" } ?? "")\(path ?? "")"
        case "ping":
            return "ping \(host)"
        default:
            return "\(mode ?? "") \(host)\(port.map { ":\($0)" } ?? "")"
        }
    }

    enum CodingKeys: String, CodingKey {
        case targetHealthCheckId, healthCheckId, name, siteId, siteName, siteNiceId, hcEnabled, hcHealth, hcMode,
             hcHostname, hcPort, hcPath, hcScheme, hcMethod, hcInterval, hcUnhealthyInterval, hcTimeout,
             hcStatus, hcFollowRedirects, hcTlsServerName, hcHealthyThreshold, hcUnhealthyThreshold,
             resourceId, resourceName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientInt(.targetHealthCheckId) ?? c.lenientInt(.healthCheckId) else {
            throw DecodingError.keyNotFound(CodingKeys.targetHealthCheckId,
                                            .init(codingPath: c.codingPath, debugDescription: "targetHealthCheckId"))
        }
        healthCheckId = id
        name = c.lenientString(.name) ?? "Health-Check \(id)"
        siteId = c.lenientInt(.siteId)
        siteName = c.lenientString(.siteName)
        siteNiceId = c.lenientString(.siteNiceId)
        enabled = c.lenientBool(.hcEnabled) ?? false
        health = c.lenientString(.hcHealth)
        mode = c.lenientString(.hcMode)
        hostname = c.lenientString(.hcHostname)
        port = c.lenientInt(.hcPort)
        path = c.lenientString(.hcPath)
        scheme = c.lenientString(.hcScheme)
        method = c.lenientString(.hcMethod)
        interval = c.lenientInt(.hcInterval)
        unhealthyInterval = c.lenientInt(.hcUnhealthyInterval)
        timeout = c.lenientInt(.hcTimeout)
        expectedStatus = c.lenientInt(.hcStatus)
        followRedirects = c.lenientBool(.hcFollowRedirects)
        tlsServerName = c.lenientString(.hcTlsServerName)
        healthyThreshold = c.lenientInt(.hcHealthyThreshold)
        unhealthyThreshold = c.lenientInt(.hcUnhealthyThreshold)
        resourceId = c.lenientInt(.resourceId)
        resourceName = c.lenientString(.resourceName)
    }
}

/// Body for `PUT /org/{orgId}/health-check` (create) and `POST …/health-check/{id}` (update).
/// For updates, only non-nil fields are sent.
public struct HealthCheckBody: Encodable, Sendable, Equatable {
    public var name: String?
    public var siteId: Int?
    public var hcEnabled: Bool?
    public var hcMode: HealthCheckMode?
    /// Required when the check is enabled.
    public var hcHostname: String?
    public var hcPort: Int?
    public var hcPath: String?
    /// `http` or `https`.
    public var hcScheme: String?
    public var hcMethod: String?
    /// Seconds between checks while healthy.
    public var hcInterval: Int?
    /// Seconds between checks while unhealthy.
    public var hcUnhealthyInterval: Int?
    /// Timeout in seconds.
    public var hcTimeout: Int?
    /// Expected HTTP status code; `nil` accepts any 2xx.
    public var hcStatus: Int?
    public var hcFollowRedirects: Bool?
    public var hcTlsServerName: String?
    public var hcHealthyThreshold: Int?
    public var hcUnhealthyThreshold: Int?

    public init(name: String? = nil, siteId: Int? = nil, hcEnabled: Bool? = nil, hcMode: HealthCheckMode? = nil,
                hcHostname: String? = nil, hcPort: Int? = nil, hcPath: String? = nil, hcScheme: String? = nil,
                hcMethod: String? = nil, hcInterval: Int? = nil, hcUnhealthyInterval: Int? = nil,
                hcTimeout: Int? = nil, hcStatus: Int? = nil, hcFollowRedirects: Bool? = nil,
                hcTlsServerName: String? = nil, hcHealthyThreshold: Int? = nil, hcUnhealthyThreshold: Int? = nil) {
        self.name = name
        self.siteId = siteId
        self.hcEnabled = hcEnabled
        self.hcMode = hcMode
        self.hcHostname = hcHostname
        self.hcPort = hcPort
        self.hcPath = hcPath
        self.hcScheme = hcScheme
        self.hcMethod = hcMethod
        self.hcInterval = hcInterval
        self.hcUnhealthyInterval = hcUnhealthyInterval
        self.hcTimeout = hcTimeout
        self.hcStatus = hcStatus
        self.hcFollowRedirects = hcFollowRedirects
        self.hcTlsServerName = hcTlsServerName
        self.hcHealthyThreshold = hcHealthyThreshold
        self.hcUnhealthyThreshold = hcUnhealthyThreshold
    }
}

struct CreatedHealthCheck: Decodable {
    let targetHealthCheckId: Int
}

// MARK: - Alert rules (Enterprise)

public enum AlertEventType: String, Sendable, CaseIterable, Codable {
    case siteOnline = "site_online"
    case siteOffline = "site_offline"
    case siteToggle = "site_toggle"
    case healthCheckHealthy = "health_check_healthy"
    case healthCheckUnhealthy = "health_check_unhealthy"
    case healthCheckToggle = "health_check_toggle"
    case resourceHealthy = "resource_healthy"
    case resourceUnhealthy = "resource_unhealthy"
    case resourceDegraded = "resource_degraded"
    case resourceToggle = "resource_toggle"

    public enum Source: Sendable { case site, healthCheck, resource }

    public var source: Source {
        switch self {
        case .siteOnline, .siteOffline, .siteToggle: .site
        case .healthCheckHealthy, .healthCheckUnhealthy, .healthCheckToggle: .healthCheck
        case .resourceHealthy, .resourceUnhealthy, .resourceDegraded, .resourceToggle: .resource
        }
    }
}

public struct AlertRecipient: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { recipientId }
    public var recipientId: Int
    public var userId: String?
    public var roleId: Int?
    public var email: String?

    enum CodingKeys: String, CodingKey { case recipientId, userId, roleId, email }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recipientId = c.lenientInt(.recipientId) ?? 0
        userId = c.lenientString(.userId)
        roleId = c.lenientInt(.roleId)
        email = c.lenientString(.email)
    }
}

public struct AlertWebhook: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { webhookActionId }
    public var webhookActionId: Int
    public var webhookUrl: String
    public var enabled: Bool
    public var lastSentAt: Date?

    enum CodingKeys: String, CodingKey { case webhookActionId, webhookUrl, enabled, lastSentAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        webhookActionId = c.lenientInt(.webhookActionId) ?? 0
        webhookUrl = c.lenientString(.webhookUrl) ?? ""
        enabled = c.lenientBool(.enabled) ?? true
        lastSentAt = c.lenientDouble(.lastSentAt).map(Date.init(pangolinTimestamp:))
    }
}

/// An alert rule (`GET /org/{orgId}/alert-rules`, `GET /org/{orgId}/alert-rule/{id}`).
/// Recipients and webhooks are only included in the detail response.
public struct AlertRule: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { alertRuleId }
    public var alertRuleId: Int
    public var orgId: String?
    public var name: String
    public var eventType: AlertEventType?
    public var eventTypeRaw: String
    public var enabled: Bool
    public var cooldownSeconds: Int
    public var lastTriggeredAt: Date?
    public var siteIds: [Int]
    public var healthCheckIds: [Int]
    public var resourceIds: [Int]
    public var allSites: Bool?
    public var allHealthChecks: Bool?
    public var allResources: Bool?
    public var recipients: [AlertRecipient]
    public var webhookActions: [AlertWebhook]

    enum CodingKeys: String, CodingKey {
        case alertRuleId, orgId, name, eventType, enabled, cooldownSeconds, lastTriggeredAt, siteIds,
             healthCheckIds, resourceIds, allSites, allHealthChecks, allResources, recipients, webhookActions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alertRuleId = c.lenientInt(.alertRuleId) ?? 0
        orgId = c.lenientString(.orgId)
        name = c.lenientString(.name) ?? ""
        eventTypeRaw = c.lenientString(.eventType) ?? ""
        eventType = AlertEventType(rawValue: eventTypeRaw)
        enabled = c.lenientBool(.enabled) ?? true
        cooldownSeconds = c.lenientInt(.cooldownSeconds) ?? 0
        lastTriggeredAt = c.lenientDouble(.lastTriggeredAt).map(Date.init(pangolinTimestamp:))
        siteIds = c.lenientArray(Int.self, .siteIds)
        healthCheckIds = c.lenientArray(Int.self, .healthCheckIds)
        resourceIds = c.lenientArray(Int.self, .resourceIds)
        allSites = c.lenientBool(.allSites)
        allHealthChecks = c.lenientBool(.allHealthChecks)
        allResources = c.lenientBool(.allResources)
        recipients = c.lenientArray(AlertRecipient.self, .recipients)
        webhookActions = c.lenientArray(AlertWebhook.self, .webhookActions)
    }
}

public struct WebhookActionBody: Encodable, Sendable, Equatable {
    public var webhookUrl: String
    public var enabled: Bool
    public init(webhookUrl: String, enabled: Bool = true) {
        self.webhookUrl = webhookUrl
        self.enabled = enabled
    }
}

/// Body for creating (`PUT /org/{orgId}/alert-rule`) or updating (`POST …/alert-rule/{id}`) an alert rule.
/// For updates, arrays that are set replace the existing set; `nil` fields are not sent.
public struct AlertRuleBody: Encodable, Sendable, Equatable {
    public var name: String?
    public var eventType: AlertEventType?
    public var enabled: Bool?
    public var cooldownSeconds: Int?
    public var siteIds: [Int]?
    public var allSites: Bool?
    public var healthCheckIds: [Int]?
    public var allHealthChecks: Bool?
    public var resourceIds: [Int]?
    public var allResources: Bool?
    public var userIds: [String]?
    public var roleIds: [Int]?
    public var emails: [String]?
    public var webhookActions: [WebhookActionBody]?

    public init(name: String? = nil, eventType: AlertEventType? = nil, enabled: Bool? = nil,
                cooldownSeconds: Int? = nil, siteIds: [Int]? = nil, allSites: Bool? = nil,
                healthCheckIds: [Int]? = nil, allHealthChecks: Bool? = nil, resourceIds: [Int]? = nil,
                allResources: Bool? = nil, userIds: [String]? = nil, roleIds: [Int]? = nil,
                emails: [String]? = nil, webhookActions: [WebhookActionBody]? = nil) {
        self.name = name
        self.eventType = eventType
        self.enabled = enabled
        self.cooldownSeconds = cooldownSeconds
        self.siteIds = siteIds
        self.allSites = allSites
        self.healthCheckIds = healthCheckIds
        self.allHealthChecks = allHealthChecks
        self.resourceIds = resourceIds
        self.allResources = allResources
        self.userIds = userIds
        self.roleIds = roleIds
        self.emails = emails
        self.webhookActions = webhookActions
    }

    /// Validation mirroring Pangolin's server-side rules. Returns a German message or `nil`.
    public var validationError: String? {
        if let name, name.trimmingCharacters(in: .whitespaces).isEmpty { return "Name fehlt." }
        guard let eventType else { return nil }
        switch eventType.source {
        case .site where allSites != true && (siteIds ?? []).isEmpty:
            return "Mindestens eine Site auswählen oder „Alle Sites“ aktivieren."
        case .healthCheck where allHealthChecks != true && (healthCheckIds ?? []).isEmpty:
            return "Mindestens einen Health-Check auswählen oder „Alle“ aktivieren."
        case .resource where allResources != true && (resourceIds ?? []).isEmpty:
            return "Mindestens eine Ressource auswählen oder „Alle Ressourcen“ aktivieren."
        default:
            break
        }
        switch eventType.source {
        case .site where !(healthCheckIds ?? []).isEmpty || !(resourceIds ?? []).isEmpty,
             .healthCheck where !(siteIds ?? []).isEmpty || !(resourceIds ?? []).isEmpty,
             .resource where !(siteIds ?? []).isEmpty || !(healthCheckIds ?? []).isEmpty:
            return "Nur Quellen passend zum Ereignistyp auswählen."
        default:
            return nil
        }
    }

    /// `true` when nobody would be notified (allowed by Pangolin, but usually a mistake).
    public var hasNoRecipients: Bool {
        (userIds ?? []).isEmpty && (roleIds ?? []).isEmpty && (emails ?? []).isEmpty && (webhookActions ?? []).isEmpty
    }
}

struct CreatedAlertRule: Decodable {
    let alertRuleId: Int
}
