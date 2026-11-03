import Foundation

// MARK: - Creating resources

extension PangolinClient {
    /// `PUT /org/{orgId}/public-resource` – creates an HTTP or raw TCP/UDP resource.
    public func createResource(orgId: String, _ body: CreateResourceBody) async throws -> PublicResource {
        try await send(.put, ["org", orgId, "public-resource"], body: body)
    }
}

// MARK: - Resource authentication

extension PangolinClient {
    /// `POST /public-resource/{id}/password` – `nil` removes the password.
    public func setResourcePassword(_ resourceId: Int, password: String?) async throws {
        try await sendAction(.post, ["public-resource", String(resourceId), "password"],
                             body: SetPasswordBody(password: password))
    }

    /// `POST /public-resource/{id}/pincode` – 6 digits, `nil` removes the PIN.
    public func setResourcePincode(_ resourceId: Int, pincode: String?) async throws {
        try await sendAction(.post, ["public-resource", String(resourceId), "pincode"],
                             body: SetPincodeBody(pincode: pincode))
    }

    /// `POST /public-resource/{id}/header-auth` – pass `.remove` to disable.
    public func setResourceHeaderAuth(_ resourceId: Int, _ body: SetHeaderAuthBody) async throws {
        try await sendAction(.post, ["public-resource", String(resourceId), "header-auth"], body: body)
    }
}

// MARK: - Resource rules

extension PangolinClient {
    /// `GET /public-resource/{id}/rules` – sorted by priority.
    public func rules(resourceId: Int, limit: Int = 1000, offset: Int = 0) async throws -> Page<ResourceRule> {
        var page: Page<ResourceRule> = try await sendList(["public-resource", String(resourceId), "rules"],
                                                          key: "rules",
                                                          query: [.int("limit", limit), .int("offset", offset)])
        page.items.sort { $0.priority < $1.priority }
        return page
    }

    /// `PUT /public-resource/{id}/rule`
    public func createRule(resourceId: Int, _ body: RuleBody) async throws {
        try await sendAction(.put, ["public-resource", String(resourceId), "rule"], body: body)
    }

    /// `POST /public-resource/{id}/rule/{ruleId}`
    public func updateRule(resourceId: Int, ruleId: Int, _ body: RuleBody) async throws {
        try await sendAction(.post, ["public-resource", String(resourceId), "rule", String(ruleId)], body: body)
    }

    /// `DELETE /public-resource/{id}/rule/{ruleId}`
    public func deleteRule(resourceId: Int, ruleId: Int) async throws {
        try await sendAction(.delete, ["public-resource", String(resourceId), "rule", String(ruleId)])
    }
}

// MARK: - Health checks (Enterprise)

extension PangolinClient {
    /// `GET /org/{orgId}/health-checks`
    public func healthChecks(orgId: String, search: String? = nil, siteId: Int? = nil,
                             limit: Int = 1000, offset: Int = 0) async throws -> Page<HealthCheck> {
        try await sendList(["org", orgId, "health-checks"], key: "healthChecks", query: [
            .int("limit", limit),
            .int("offset", offset),
            .string("query", search),
            .int("siteId", siteId)
        ])
    }

    /// `PUT /org/{orgId}/health-check` – returns the new health check ID.
    @discardableResult
    public func createHealthCheck(orgId: String, _ body: HealthCheckBody) async throws -> Int {
        try await send(.put, ["org", orgId, "health-check"], body: body, as: CreatedHealthCheck.self)
            .targetHealthCheckId
    }

    /// `POST /org/{orgId}/health-check/{id}`
    public func updateHealthCheck(orgId: String, healthCheckId: Int, _ body: HealthCheckBody) async throws {
        try await sendAction(.post, ["org", orgId, "health-check", String(healthCheckId)], body: body)
    }

    /// `DELETE /org/{orgId}/health-check/{id}`
    public func deleteHealthCheck(orgId: String, healthCheckId: Int) async throws {
        try await sendAction(.delete, ["org", orgId, "health-check", String(healthCheckId)])
    }
}

// MARK: - Alert rules (Enterprise)

extension PangolinClient {
    /// `GET /org/{orgId}/alert-rules`
    public func alertRules(orgId: String, limit: Int = 1000, offset: Int = 0) async throws -> Page<AlertRule> {
        try await sendList(["org", orgId, "alert-rules"], key: "alertRules",
                           query: [.int("limit", limit), .int("offset", offset)])
    }

    /// `GET /org/{orgId}/alert-rule/{id}` – includes recipients and webhooks.
    public func alertRule(orgId: String, alertRuleId: Int) async throws -> AlertRule {
        try await send(.get, ["org", orgId, "alert-rule", String(alertRuleId)])
    }

    /// `PUT /org/{orgId}/alert-rule` – returns the new alert rule ID.
    @discardableResult
    public func createAlertRule(orgId: String, _ body: AlertRuleBody) async throws -> Int {
        try await send(.put, ["org", orgId, "alert-rule"], body: body, as: CreatedAlertRule.self).alertRuleId
    }

    /// `POST /org/{orgId}/alert-rule/{id}`
    public func updateAlertRule(orgId: String, alertRuleId: Int, _ body: AlertRuleBody) async throws {
        try await sendAction(.post, ["org", orgId, "alert-rule", String(alertRuleId)], body: body)
    }

    /// `DELETE /org/{orgId}/alert-rule/{id}`
    public func deleteAlertRule(orgId: String, alertRuleId: Int) async throws {
        try await sendAction(.delete, ["org", orgId, "alert-rule", String(alertRuleId)])
    }
}
