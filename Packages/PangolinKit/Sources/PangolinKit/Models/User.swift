import Foundation

/// A user within an organization (`GET /org/{orgId}/users`).
public struct OrgUser: Decodable, Sendable, Hashable, Identifiable {
    /// Pangolin user ID (`users.userId`).
    public var id: String
    public var email: String?
    public var username: String?
    public var name: String?
    public var emailVerified: Bool?
    public var dateCreated: String?
    public var orgId: String?
    /// `internal` or `oidc`.
    public var type: String?
    public var isOwner: Bool?
    public var idpId: Int?
    public var idpName: String?
    public var idpType: String?
    public var twoFactorEnabled: Bool?
    public var roles: [UserRole]

    public var displayName: String {
        if let name, !name.isEmpty { return name }
        if let username, !username.isEmpty { return username }
        return email ?? id
    }

    public init(id: String, email: String? = nil, username: String? = nil, name: String? = nil) {
        self.id = id
        self.email = email
        self.username = username
        self.name = name
        self.roles = []
    }

    enum CodingKeys: String, CodingKey {
        case id, userId, email, username, name, emailVerified, dateCreated, orgId, type, isOwner, idpId,
             idpName, idpType, twoFactorEnabled, roles, roleId, roleName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientString(.id) ?? c.lenientString(.userId) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: c.codingPath, debugDescription: "id"))
        }
        self.id = id
        email = c.lenientString(.email)
        username = c.lenientString(.username)
        name = c.lenientString(.name)
        emailVerified = c.lenientBool(.emailVerified)
        dateCreated = c.lenientString(.dateCreated)
        orgId = c.lenientString(.orgId)
        type = c.lenientString(.type)
        isOwner = c.lenientBool(.isOwner)
        idpId = c.lenientInt(.idpId)
        idpName = c.lenientString(.idpName)
        idpType = c.lenientString(.idpType)
        twoFactorEnabled = c.lenientBool(.twoFactorEnabled)
        var roles = c.lenientArray(UserRole.self, .roles)
        // Older servers return a single roleId/roleName instead of a roles array.
        if roles.isEmpty, let roleId = c.lenientInt(.roleId) {
            roles = [UserRole(roleId: roleId, roleName: c.lenientString(.roleName) ?? "")]
        }
        self.roles = roles
    }
}

public struct UserRole: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { roleId }
    public var roleId: Int
    public var roleName: String

    public init(roleId: Int, roleName: String) {
        self.roleId = roleId
        self.roleName = roleName
    }

    enum CodingKeys: String, CodingKey { case roleId, roleName, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roleId = c.lenientInt(.roleId) ?? 0
        roleName = c.lenientString(.roleName) ?? c.lenientString(.name) ?? ""
    }
}

/// A role in an organization.
public struct Role: Decodable, Sendable, Hashable, Identifiable {
    public var id: Int { roleId }
    public var roleId: Int
    public var orgId: String?
    public var name: String
    public var description: String?
    public var isAdmin: Bool?
    public var requireDeviceApproval: Bool?

    public init(roleId: Int, name: String, isAdmin: Bool? = nil) {
        self.roleId = roleId
        self.name = name
        self.isAdmin = isAdmin
    }

    enum CodingKeys: String, CodingKey { case roleId, orgId, name, description, isAdmin, requireDeviceApproval }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roleId = c.lenientInt(.roleId) ?? 0
        orgId = c.lenientString(.orgId)
        name = c.lenientString(.name) ?? ""
        description = c.lenientString(.description)
        isAdmin = c.lenientBool(.isAdmin)
        requireDeviceApproval = c.lenientBool(.requireDeviceApproval)
    }
}

/// Body for `PUT /org/{orgId}/role`.
public struct CreateRoleBody: Encodable, Sendable {
    public var name: String
    public var description: String?
    public var requireDeviceApproval: Bool?

    public init(name: String, description: String? = nil, requireDeviceApproval: Bool? = nil) {
        self.name = name
        self.description = description
        self.requireDeviceApproval = requireDeviceApproval
    }
}

/// An open invitation (`GET /org/{orgId}/invitations`).
public struct Invitation: Decodable, Sendable, Hashable, Identifiable {
    public var id: String { inviteId }
    public var inviteId: String
    public var email: String
    public var expiresAt: Date?
    public var roles: [UserRole]

    enum CodingKeys: String, CodingKey { case inviteId, email, expiresAt, roles }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inviteId = c.lenientString(.inviteId) ?? ""
        email = c.lenientString(.email) ?? ""
        if let value = c.lenientDouble(.expiresAt) {
            expiresAt = Date(pangolinTimestamp: value)
        } else {
            expiresAt = c.lenientString(.expiresAt).flatMap(Date.init(pangolinString:))
        }
        roles = c.lenientArray(UserRole.self, .roles)
    }
}

/// Body for `POST /org/{orgId}/create-invite`.
public struct CreateInviteBody: Encodable, Sendable {
    public var email: String
    public var roleIds: [Int]
    /// 1…168 hours.
    public var validHours: Int
    public var sendEmail: Bool?
    public var regenerate: Bool?

    public init(email: String, roleIds: [Int], validHours: Int = 72, sendEmail: Bool? = true,
                regenerate: Bool? = nil) {
        self.email = email
        self.roleIds = roleIds
        self.validHours = min(max(validHours, 1), 168)
        self.sendEmail = sendEmail
        self.regenerate = regenerate
    }
}

/// Result of creating an invitation.
public struct InviteResult: Decodable, Sendable, Hashable {
    public var inviteLink: String
    public var expiresAt: Date?

    enum CodingKeys: String, CodingKey { case inviteLink, expiresAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inviteLink = c.lenientString(.inviteLink) ?? ""
        expiresAt = c.lenientDouble(.expiresAt).map(Date.init(pangolinTimestamp:))
    }
}

/// Filters for `GET /org/{orgId}/users`.
public struct UserQuery: Sendable, Equatable {
    public var search: String?
    public init(search: String? = nil) { self.search = search }
}
