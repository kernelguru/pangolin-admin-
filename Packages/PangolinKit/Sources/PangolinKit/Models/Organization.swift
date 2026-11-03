import Foundation

/// An organization (`/org/{orgId}`, `/orgs`).
public struct Organization: Decodable, Sendable, Hashable, Identifiable {
    public var id: String { orgId }
    public var orgId: String
    public var name: String
    public var subnet: String?
    public var utilitySubnet: String?
    public var createdAt: String?
    public var requireTwoFactor: Bool?
    public var maxSessionLengthHours: Int?
    public var passwordExpiryDays: Int?
    public var settingsLogRetentionDaysRequest: Int?
    public var settingsLogRetentionDaysAccess: Int?
    public var settingsLogRetentionDaysAction: Int?

    public init(orgId: String, name: String) {
        self.orgId = orgId
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case orgId, name, subnet, utilitySubnet, createdAt, requireTwoFactor, maxSessionLengthHours,
             passwordExpiryDays, settingsLogRetentionDaysRequest, settingsLogRetentionDaysAccess,
             settingsLogRetentionDaysAction
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        orgId = try c.decode(String.self, forKey: .orgId)
        name = c.lenientString(.name) ?? orgId
        subnet = c.lenientString(.subnet)
        utilitySubnet = c.lenientString(.utilitySubnet)
        createdAt = c.lenientString(.createdAt)
        requireTwoFactor = c.lenientBool(.requireTwoFactor)
        maxSessionLengthHours = c.lenientInt(.maxSessionLengthHours)
        passwordExpiryDays = c.lenientInt(.passwordExpiryDays)
        settingsLogRetentionDaysRequest = c.lenientInt(.settingsLogRetentionDaysRequest)
        settingsLogRetentionDaysAccess = c.lenientInt(.settingsLogRetentionDaysAccess)
        settingsLogRetentionDaysAction = c.lenientInt(.settingsLogRetentionDaysAction)
    }
}

/// `GET /org/{orgId}` wraps the org in `{ "org": {…} }`.
struct OrganizationPayload: Decodable {
    let org: Organization
}

/// Body for `POST /org/{orgId}`.
public struct UpdateOrganizationBody: Encodable, Sendable {
    public var name: String?
    public var requireTwoFactor: Bool?
    public var maxSessionLengthHours: Int?
    public var passwordExpiryDays: Int?

    public init(name: String? = nil, requireTwoFactor: Bool? = nil,
                maxSessionLengthHours: Int? = nil, passwordExpiryDays: Int? = nil) {
        self.name = name
        self.requireTwoFactor = requireTwoFactor
        self.maxSessionLengthHours = maxSessionLengthHours
        self.passwordExpiryDays = passwordExpiryDays
    }
}
