import Foundation

// MARK: - Server

extension PangolinClient {
    /// `GET /` – health check of the Integration API. Does not validate the API key.
    public func healthCheck() async throws {
        _ = try await sendRaw(.get, [])
    }

    /// Checks reachability **and** the API key against an organization.
    /// With a root key and no `orgId`, `/orgs` is used instead.
    @discardableResult
    public func verifyAccess(orgId: String?) async throws -> [Organization] {
        if let orgId, !orgId.isEmpty {
            return [try await organization(orgId)]
        }
        return try await organizations().items
    }
}

// MARK: - Organizations

extension PangolinClient {
    /// `GET /orgs` – **requires a root API key**.
    public func organizations(limit: Int = 1000, offset: Int = 0) async throws -> Page<Organization> {
        try await sendList(["orgs"], key: "orgs", query: [.int("limit", limit), .int("offset", offset)])
    }

    /// `GET /org/{orgId}`
    public func organization(_ orgId: String) async throws -> Organization {
        try await send(.get, ["org", orgId], as: OrganizationPayload.self).org
    }

    /// `POST /org/{orgId}`
    public func updateOrganization(_ orgId: String, _ body: UpdateOrganizationBody) async throws {
        try await sendAction(.post, ["org", orgId], body: body)
    }

    /// `POST /org/{orgId}/reset-bandwidth` – resets all site traffic counters.
    public func resetBandwidth(orgId: String) async throws {
        try await sendAction(.post, ["org", orgId, "reset-bandwidth"])
    }
}

// MARK: - Sites

extension PangolinClient {
    /// `GET /org/{orgId}/sites`
    public func sites(orgId: String, query: SiteQuery = SiteQuery(),
                      page: PageRequest = PageRequest()) async throws -> Page<Site> {
        try await sendList(["org", orgId, "sites"], key: "sites", query: [
            .int("page", page.page),
            .int("pageSize", page.pageSize),
            .string("query", query.search),
            .bool("online", query.online),
            .string("status", query.status),
            .string("sort_by", query.sortBy?.rawValue),
            .string("order", query.order?.rawValue)
        ])
    }

    /// All sites of an organization (pages through the list).
    public func allSites(orgId: String, query: SiteQuery = SiteQuery()) async throws -> [Site] {
        try await fetchAll { try await self.sites(orgId: orgId, query: query, page: $0) }
    }

    /// `GET /site/{siteId}`
    public func site(_ siteId: Int) async throws -> Site {
        try await send(.get, ["site", String(siteId)])
    }

    /// `POST /site/{siteId}`
    public func updateSite(_ siteId: Int, _ body: UpdateSiteBody) async throws {
        try await sendAction(.post, ["site", String(siteId)], body: body)
    }

    /// `DELETE /site/{siteId}` – deletes the site and all associated data.
    public func deleteSite(_ siteId: Int) async throws {
        try await sendAction(.delete, ["site", String(siteId)])
    }

    /// `POST /site/{siteId}/restart`
    public func restartSite(_ siteId: Int) async throws {
        try await sendAction(.post, ["site", String(siteId), "restart"])
    }

    /// `POST /site/{siteId}/approve` – approves a pending site.
    public func approveSite(_ siteId: Int) async throws {
        try await sendAction(.post, ["site", String(siteId), "approve"])
    }

    /// `POST /site/{siteId}/reject` – rejects (deletes) a pending site.
    public func rejectSite(_ siteId: Int) async throws {
        try await sendAction(.post, ["site", String(siteId), "reject"])
    }
}

// MARK: - Public resources & targets

extension PangolinClient {
    /// `GET /org/{orgId}/public-resources`
    public func resources(orgId: String, query: ResourceQuery = ResourceQuery(),
                          page: PageRequest = PageRequest()) async throws -> Page<PublicResource> {
        try await sendList(["org", orgId, "public-resources"], key: "resources", query: [
            .int("page", page.page),
            .int("pageSize", page.pageSize),
            .string("query", query.search),
            .bool("enabled", query.enabled),
            .string("authState", query.authState?.rawValue),
            .string("healthStatus", query.health?.rawValue),
            .string("order", query.order?.rawValue)
        ])
    }

    /// All public resources of an organization.
    public func allResources(orgId: String, query: ResourceQuery = ResourceQuery()) async throws -> [PublicResource] {
        try await fetchAll { try await self.resources(orgId: orgId, query: query, page: $0) }
    }

    /// `GET /public-resource/{resourceId}`
    public func resource(_ resourceId: Int) async throws -> PublicResource {
        try await send(.get, ["public-resource", String(resourceId)])
    }

    /// `POST /public-resource/{resourceId}`
    public func updateResource(_ resourceId: Int, _ body: UpdateResourceBody) async throws {
        try await sendAction(.post, ["public-resource", String(resourceId)], body: body)
    }

    /// Enables or disables a resource.
    public func setResourceEnabled(_ resourceId: Int, enabled: Bool) async throws {
        try await updateResource(resourceId, UpdateResourceBody(enabled: enabled))
    }

    /// `DELETE /public-resource/{resourceId}`
    public func deleteResource(_ resourceId: Int) async throws {
        try await sendAction(.delete, ["public-resource", String(resourceId)])
    }

    /// `GET /public-resource/{resourceId}/targets`
    public func targets(resourceId: Int, limit: Int = 1000, offset: Int = 0) async throws -> Page<Target> {
        try await sendList(["public-resource", String(resourceId), "targets"], key: "targets",
                           query: [.int("limit", limit), .int("offset", offset)])
    }

    /// `PUT /public-resource/{resourceId}/target`
    public func createTarget(resourceId: Int, _ body: CreateTargetBody) async throws -> Target {
        try await send(.put, ["public-resource", String(resourceId), "target"], body: body)
    }

    /// `POST /target/{targetId}`
    public func updateTarget(_ targetId: Int, _ body: UpdateTargetBody) async throws {
        try await sendAction(.post, ["target", String(targetId)], body: body)
    }

    /// `DELETE /target/{targetId}`
    public func deleteTarget(_ targetId: Int) async throws {
        try await sendAction(.delete, ["target", String(targetId)])
    }
}

// MARK: - Clients

extension PangolinClient {
    /// `GET /org/{orgId}/clients` – **machine clients only** (clients without a user).
    public func clients(orgId: String, query: ClientQuery = ClientQuery(),
                        page: PageRequest = PageRequest()) async throws -> Page<Client> {
        try await sendList(["org", orgId, "clients"], key: "clients", query: [
            .int("page", page.page),
            .int("pageSize", page.pageSize),
            .string("query", query.search),
            .bool("online", query.online),
            .string("status", query.statusValue)
        ])
    }

    /// `GET /org/{orgId}/user-devices` – VPN clients (Olm) that belong to users.
    public func userDevices(orgId: String, query: ClientQuery = ClientQuery(),
                            page: PageRequest = PageRequest()) async throws -> Page<Client> {
        try await sendList(["org", orgId, "user-devices"], key: "devices", query: [
            .int("page", page.page),
            .int("pageSize", page.pageSize),
            .string("query", query.search),
            .bool("online", query.online),
            .string("status", query.statusValue)
        ])
    }

    /// All machine clients and user devices of an organization, in every status
    /// (active, pending, denied, blocked, archived).
    public func allClients(orgId: String, search: String? = nil) async throws -> [Client] {
        let machineQuery = ClientQuery(search: search, statuses: [.active, .blocked, .archived])
        let deviceQuery = ClientQuery(search: search, statuses: ClientStatus.allCases)
        async let machines = capture { try await self.fetchAll { try await self.clients(orgId: orgId, query: machineQuery, page: $0) } }
        async let devices = capture { try await self.fetchAll { try await self.userDevices(orgId: orgId, query: deviceQuery, page: $0) } }
        let (machineResult, deviceResult) = await (machines, devices)

        // A key may be allowed to list only one of the two kinds – show what is available.
        switch (deviceResult, machineResult) {
        case (.failure(let error), .failure):
            throw error
        default:
            var seen = Set<Int>()
            let all = ((try? deviceResult.get()) ?? []) + ((try? machineResult.get()) ?? [])
            return all.filter { seen.insert($0.clientId).inserted }
        }
    }

    /// `GET /client/{clientId}`
    public func client(_ clientId: Int) async throws -> Client {
        try await send(.get, ["client", String(clientId)])
    }

    /// `POST /client/{clientId}/block`
    public func blockClient(_ clientId: Int) async throws {
        try await sendAction(.post, ["client", String(clientId), "block"])
    }

    /// `POST /client/{clientId}/unblock`
    public func unblockClient(_ clientId: Int) async throws {
        try await sendAction(.post, ["client", String(clientId), "unblock"])
    }

    /// `POST /client/{clientId}/archive`
    public func archiveClient(_ clientId: Int) async throws {
        try await sendAction(.post, ["client", String(clientId), "archive"])
    }

    /// `POST /client/{clientId}/unarchive`
    public func unarchiveClient(_ clientId: Int) async throws {
        try await sendAction(.post, ["client", String(clientId), "unarchive"])
    }

    /// `DELETE /client/{clientId}`
    public func deleteClient(_ clientId: Int) async throws {
        try await sendAction(.delete, ["client", String(clientId)])
    }
}

// MARK: - Users, roles & invitations

extension PangolinClient {
    /// `GET /org/{orgId}/users`
    public func users(orgId: String, query: UserQuery = UserQuery(),
                      page: PageRequest = PageRequest()) async throws -> Page<OrgUser> {
        try await sendList(["org", orgId, "users"], key: "users", query: [
            .int("page", page.page),
            .int("pageSize", page.pageSize),
            .string("query", query.search)
        ])
    }

    /// All users of an organization.
    public func allUsers(orgId: String, query: UserQuery = UserQuery()) async throws -> [OrgUser] {
        try await fetchAll { try await self.users(orgId: orgId, query: query, page: $0) }
    }

    /// `DELETE /org/{orgId}/user/{userId}` – removes the user from the organization.
    public func removeUser(orgId: String, userId: String) async throws {
        try await sendAction(.delete, ["org", orgId, "user", userId])
    }

    /// `POST /user/{userId}/add-role/{roleId}`
    public func addRole(_ roleId: Int, toUser userId: String) async throws {
        try await sendAction(.post, ["user", userId, "add-role", String(roleId)])
    }

    /// `DELETE /user/{userId}/remove-role/{roleId}` – a user must keep at least one role.
    public func removeRole(_ roleId: Int, fromUser userId: String) async throws {
        try await sendAction(.delete, ["user", userId, "remove-role", String(roleId)])
    }

    /// `GET /org/{orgId}/roles`
    public func roles(orgId: String, page: PageRequest = PageRequest()) async throws -> Page<Role> {
        try await sendList(["org", orgId, "roles"], key: "roles",
                           query: [.int("page", page.page), .int("pageSize", page.pageSize)])
    }

    /// All roles of an organization.
    public func allRoles(orgId: String) async throws -> [Role] {
        try await fetchAll { try await self.roles(orgId: orgId, page: $0) }
    }

    /// `PUT /org/{orgId}/role`
    public func createRole(orgId: String, _ body: CreateRoleBody) async throws -> Role {
        try await send(.put, ["org", orgId, "role"], body: body)
    }

    /// `DELETE /role/{roleId}`
    public func deleteRole(_ roleId: Int) async throws {
        try await sendAction(.delete, ["role", String(roleId)])
    }

    /// `GET /org/{orgId}/invitations`
    public func invitations(orgId: String, limit: Int = 1000, offset: Int = 0) async throws -> Page<Invitation> {
        try await sendList(["org", orgId, "invitations"], key: "invitations",
                           query: [.int("limit", limit), .int("offset", offset)])
    }

    /// `POST /org/{orgId}/create-invite`
    public func invite(orgId: String, _ body: CreateInviteBody) async throws -> InviteResult {
        try await send(.post, ["org", orgId, "create-invite"], body: body)
    }

    /// `DELETE /org/{orgId}/invitations/{inviteId}`
    public func deleteInvitation(orgId: String, inviteId: String) async throws {
        try await sendAction(.delete, ["org", orgId, "invitations", inviteId])
    }
}

// MARK: - Domains

extension PangolinClient {
    /// `GET /org/{orgId}/domains`
    public func domains(orgId: String, limit: Int = 1000, offset: Int = 0) async throws -> Page<Domain> {
        try await sendList(["org", orgId, "domains"], key: "domains",
                           query: [.int("limit", limit), .int("offset", offset)])
    }
}

// MARK: - Audit logs

extension PangolinClient {
    /// `GET /org/{orgId}/logs/request` – requests through Pangolin's reverse proxy.
    public func requestLogs(orgId: String, _ query: LogQuery = LogQuery()) async throws -> Page<RequestLogEntry> {
        try await sendList(["org", orgId, "logs", "request"], key: "log", query: query.queryItems)
    }

    /// `GET /org/{orgId}/logs/action` – configuration changes (who changed what).
    public func actionLogs(orgId: String, _ query: LogQuery = LogQuery()) async throws -> Page<ActionLogEntry> {
        var items = query.queryItems
        items.removeAll { $0.name == "action" || $0.name == "resourceId" }
        return try await sendList(["org", orgId, "logs", "action"], key: "log", query: items)
    }

    /// `GET /org/{orgId}/logs/access` – logins and resource authentication.
    public func accessLogs(orgId: String, _ query: LogQuery = LogQuery()) async throws -> Page<AccessLogEntry> {
        var items = query.queryItems
        items.removeAll { $0.name == "action" }
        return try await sendList(["org", orgId, "logs", "access"], key: "log", query: items)
    }

    /// `GET /org/{orgId}/logs/request/export` – raw CSV.
    public func exportRequestLogsCSV(orgId: String, _ query: LogQuery = LogQuery()) async throws -> Data {
        try await sendRaw(.get, ["org", orgId, "logs", "request", "export"], query: query.queryItems)
    }
}

/// Runs an operation and returns its result instead of throwing.
func capture<T: Sendable>(_ operation: @Sendable () async throws -> T) async -> Result<T, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}
