import Foundation

/// Every Pangolin response is wrapped in this envelope:
/// `{ "data": …, "success": true, "error": false, "message": "…", "status": 200 }`
struct Envelope<T: Decodable>: Decodable {
    let data: T?
    let success: Bool?
    let error: Bool?
    let message: String?
    let status: Int?
}

/// Decodes and ignores whatever `data` contains. Used for actions whose payload we do not need.
public struct EmptyPayload: Decodable, Sendable, Equatable {
    public init() {}
    public init(from decoder: Decoder) throws {}
}

/// Pagination block. Pangolin uses two styles depending on the endpoint:
/// `page`/`pageSize` (sites, resources, clients, users, roles) and
/// `limit`/`offset` (orgs, targets, domains, invitations, logs).
public struct Pagination: Decodable, Sendable, Equatable {
    public var total: Int?
    public var page: Int?
    public var pageSize: Int?
    public var limit: Int?
    public var offset: Int?

    public init(total: Int? = nil, page: Int? = nil, pageSize: Int? = nil, limit: Int? = nil, offset: Int? = nil) {
        self.total = total
        self.page = page
        self.pageSize = pageSize
        self.limit = limit
        self.offset = offset
    }

    enum CodingKeys: String, CodingKey { case total, page, pageSize, limit, offset }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = c.lenientInt(.total)
        page = c.lenientInt(.page)
        pageSize = c.lenientInt(.pageSize)
        limit = c.lenientInt(.limit)
        offset = c.lenientInt(.offset)
    }
}

/// A page of results from a list endpoint.
public struct Page<Item: Sendable>: Sendable {
    public var items: [Item]
    public var pagination: Pagination?

    public init(items: [Item], pagination: Pagination?) {
        self.items = items
        self.pagination = pagination
    }

    /// Total number of items on the server, falling back to the items on this page.
    public var total: Int { pagination?.total ?? items.count }
}

extension Page: Equatable where Item: Equatable {}

/// Decodes `{ "<key>": [Item], "pagination": {…} }` where `<key>` is passed through `userInfo`.
struct ListPayload<Item: Decodable & Sendable>: Decodable {
    let items: [Item]
    let pagination: Pagination?

    init(from decoder: Decoder) throws {
        guard let key = decoder.userInfo[.pangolinListKey] as? String else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Missing list key"))
        }
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        items = try c.decodeIfPresent([Item].self, forKey: AnyCodingKey(key)) ?? []
        pagination = try? c.decodeIfPresent(Pagination.self, forKey: AnyCodingKey("pagination"))
    }
}

extension CodingUserInfoKey {
    static let pangolinListKey = CodingUserInfoKey(rawValue: "pangolin.listKey")!
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}
