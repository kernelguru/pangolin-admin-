import Foundation

/// Entry of the request audit log (`GET /org/{orgId}/logs/request`).
public struct RequestLogEntry: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var timestamp: Date
    /// `true` = allowed, `false` = denied.
    public var allowed: Bool
    /// Numeric reason code from Pangolin.
    public var reason: Int?
    public var actorType: String?
    public var actor: String?
    public var resourceId: Int?
    public var resourceName: String?
    public var ip: String?
    public var location: String?
    public var userAgent: String?
    public var scheme: String?
    public var host: String?
    public var path: String?
    public var method: String?
    public var tls: Bool?

    public var url: String {
        "\(scheme.map { "\($0)://" } ?? "")\(host ?? "")\(path ?? "")"
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, action, reason, actorType, actor, resourceId, resourceName, ip, location,
             userAgent, scheme, host, path, method, tls
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ts = c.lenientDouble(.timestamp) ?? 0
        timestamp = Date(pangolinTimestamp: ts)
        allowed = c.lenientBool(.action) ?? false
        reason = c.lenientInt(.reason)
        actorType = c.lenientString(.actorType)
        actor = c.lenientString(.actor)
        resourceId = c.lenientInt(.resourceId)
        resourceName = c.lenientString(.resourceName)
        ip = c.lenientString(.ip)
        location = c.lenientString(.location)
        userAgent = c.lenientString(.userAgent)
        scheme = c.lenientString(.scheme)
        host = c.lenientString(.host)
        path = c.lenientString(.path)
        method = c.lenientString(.method)
        tls = c.lenientBool(.tls)
        id = c.lenientString(.id) ?? "\(ts)-\(ip ?? "")-\(path ?? "")-\(UUID().uuidString)"
    }
}

/// Entry of the action audit log (`GET /org/{orgId}/logs/action`) – who changed what.
public struct ActionLogEntry: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var timestamp: Date
    public var action: String
    public var actorType: String?
    public var actor: String?
    public var actorId: String?
    public var metadata: String?

    enum CodingKeys: String, CodingKey { case id, timestamp, action, actorType, actor, actorId, metadata }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ts = c.lenientDouble(.timestamp) ?? 0
        timestamp = Date(pangolinTimestamp: ts)
        action = c.lenientString(.action) ?? ""
        actorType = c.lenientString(.actorType)
        actor = c.lenientString(.actor)
        actorId = c.lenientString(.actorId)
        metadata = c.lenientString(.metadata)
        id = c.lenientString(.id) ?? "\(ts)-\(action)-\(actorId ?? "")-\(UUID().uuidString)"
    }
}

/// Entry of the access audit log (`GET /org/{orgId}/logs/access`) – logins and resource access.
public struct AccessLogEntry: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var timestamp: Date
    public var allowed: Bool
    public var type: String?
    public var actorType: String?
    public var actor: String?
    public var resourceId: Int?
    public var resourceName: String?
    public var ip: String?
    public var location: String?
    public var userAgent: String?

    enum CodingKeys: String, CodingKey {
        case id, timestamp, action, type, actorType, actor, resourceId, resourceName, ip, location, userAgent
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ts = c.lenientDouble(.timestamp) ?? 0
        timestamp = Date(pangolinTimestamp: ts)
        allowed = c.lenientBool(.action) ?? false
        type = c.lenientString(.type)
        actorType = c.lenientString(.actorType)
        actor = c.lenientString(.actor)
        resourceId = c.lenientInt(.resourceId)
        resourceName = c.lenientString(.resourceName)
        ip = c.lenientString(.ip)
        location = c.lenientString(.location)
        userAgent = c.lenientString(.userAgent)
        id = c.lenientString(.id) ?? "\(ts)-\(ip ?? "")-\(type ?? "")-\(UUID().uuidString)"
    }
}

/// Time range and paging for log queries. Pangolin defaults to the last 7 days.
public struct LogQuery: Sendable, Equatable {
    public var start: Date?
    public var end: Date?
    public var limit: Int
    public var offset: Int
    public var actor: String?
    public var resourceId: Int?
    /// Request log only: filter allowed (`true`) or denied (`false`) requests.
    public var allowed: Bool?

    public init(start: Date? = nil, end: Date? = nil, limit: Int = 100, offset: Int = 0,
                actor: String? = nil, resourceId: Int? = nil, allowed: Bool? = nil) {
        self.start = start
        self.end = end
        self.limit = limit
        self.offset = offset
        self.actor = actor
        self.resourceId = resourceId
        self.allowed = allowed
    }

    /// The last `hours` hours.
    public static func last(hours: Int, limit: Int = 100) -> LogQuery {
        LogQuery(start: Date().addingTimeInterval(-Double(hours) * 3600), end: Date(), limit: limit)
    }

    var queryItems: [URLQueryItem] {
        [
            .date("timeStart", start),
            .date("timeEnd", end),
            .int("limit", limit),
            .int("offset", offset),
            .string("actor", actor),
            .int("resourceId", resourceId),
            .bool("action", allowed)
        ]
    }
}
