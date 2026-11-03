import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PangolinKit

final class ManagementTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.lastBody = nil
        super.tearDown()
    }

    private func sentJSON() throws -> [String: Any] {
        let body = try XCTUnwrap(MockURLProtocol.lastBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    // MARK: Resources & targets

    func testCreateHttpResource() async throws {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.ok(#"{"resourceId":42,"niceId":"grafana","name":"Grafana","fullDomain":"grafana.example.com","enabled":true,"ssl":true}"#)
        }
        let resource = try await MockURLProtocol.makeClient().createResource(
            orgId: "home", .http(name: "Grafana", domainId: "d1", subdomain: "grafana"))

        XCTAssertEqual(resource.resourceId, 42)
        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/v1/org/home/public-resource")
        let json = try sentJSON()
        XCTAssertEqual(json["mode"] as? String, "http")
        XCTAssertEqual(json["domainId"] as? String, "d1")
        XCTAssertEqual(json["subdomain"] as? String, "grafana")
        XCTAssertNil(json["proxyPort"])
    }

    func testCreateRawResourceSendsOnlyAllowedFields() async throws {
        MockURLProtocol.handler = { _ in MockURLProtocol.ok(#"{"resourceId":43,"name":"SSH","proxyPort":2222}"#) }
        _ = try await MockURLProtocol.makeClient().createResource(
            orgId: "home", CreateResourceBody(name: "SSH", mode: .tcp, domainId: "ignored", proxyPort: 2222))
        let json = try sentJSON()
        XCTAssertEqual(Set(json.keys), ["name", "mode", "proxyPort"])
        XCTAssertEqual(json["proxyPort"] as? Int, 2222)
    }

    func testCreateTarget() async throws {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.ok(#"{"targetId":9,"resourceId":42,"siteId":1,"ip":"10.0.0.5","port":3000,"method":"http","enabled":true}"#)
        }
        let target = try await MockURLProtocol.makeClient().createTarget(
            resourceId: 42, CreateTargetBody(siteId: 1, ip: "10.0.0.5", port: 3000, method: "http"))
        XCTAssertEqual(target.targetId, 9)
        XCTAssertEqual(target.displayAddress, "http://10.0.0.5:3000")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/v1/public-resource/42/target")
    }

    // MARK: Auth

    func testRemovePasswordSendsExplicitNull() async throws {
        MockURLProtocol.handler = { _ in MockURLProtocol.ok("null") }
        try await MockURLProtocol.makeClient().setResourcePassword(7, password: nil)
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/v1/public-resource/7/password")
        XCTAssertEqual(String(data: MockURLProtocol.lastBody!, encoding: .utf8), #"{"password":null}"#)
    }

    func testSetPincode() async throws {
        MockURLProtocol.handler = { _ in MockURLProtocol.ok("null") }
        try await MockURLProtocol.makeClient().setResourcePincode(7, pincode: "123456")
        XCTAssertEqual(try sentJSON()["pincode"] as? String, "123456")
        XCTAssertTrue(PangolinValidation.isValidPincode("123456"))
        XCTAssertFalse(PangolinValidation.isValidPincode("12345a"))
        XCTAssertFalse(PangolinValidation.isValidPincode("１２３４５６"), "Full-width digits are rejected")
        XCTAssertFalse(PangolinValidation.isValidPassword("abc"))
    }

    // MARK: Rules

    func testRulesAreSortedAndDecoded() async throws {
        let json = """
        {"rules":[
          {"ruleId":2,"resourceId":7,"action":"DROP","match":"COUNTRY","value":"RU","priority":20,"enabled":1},
          {"ruleId":1,"resourceId":7,"action":"ACCEPT","match":"CIDR","value":"10.0.0.0/8","priority":10,"enabled":true},
          {"ruleId":3,"resourceId":7,"action":"FUTURE","match":"NEW","value":"x","priority":30,"enabled":false}
        ],"pagination":{"total":3,"limit":1000,"offset":0}}
        """
        MockURLProtocol.handler = { _ in MockURLProtocol.ok(json) }
        let rules = try await MockURLProtocol.makeClient().rules(resourceId: 7).items

        XCTAssertEqual(rules.map(\.ruleId), [1, 2, 3])
        XCTAssertEqual(rules[0].action, .accept)
        XCTAssertEqual(rules[1].match, .country)
        XCTAssertTrue(rules[1].enabled)
        XCTAssertNil(rules[2].action, "Unknown values must not break decoding")
        XCTAssertEqual(rules[2].actionRaw, "FUTURE")
    }

    func testCreateAndUpdateRule() async throws {
        MockURLProtocol.handler = { _ in MockURLProtocol.ok("{}") }
        let client = MockURLProtocol.makeClient()
        let body = RuleBody(action: .drop, match: .ip, value: "1.2.3.4", priority: 5)

        try await client.createRule(resourceId: 7, body)
        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "PUT")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/v1/public-resource/7/rule")
        XCTAssertEqual(try sentJSON()["action"] as? String, "DROP")

        try await client.updateRule(resourceId: 7, ruleId: 3, body)
        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/v1/public-resource/7/rule/3")

        try await client.deleteRule(resourceId: 7, ruleId: 3)
        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "DELETE")
    }

    // MARK: Health checks

    func testHealthChecks() async throws {
        let json = """
        {"healthChecks":[{"targetHealthCheckId":5,"name":"NAS","siteId":1,"siteName":"Home Lab","hcEnabled":true,
          "hcHealth":"unhealthy","hcMode":"http","hcHostname":"10.0.0.9","hcPort":5000,"hcPath":"/health",
          "hcScheme":"https","hcMethod":"GET","hcInterval":30,"hcTimeout":5,"resourceId":null}],
         "pagination":{"total":1,"limit":1000,"offset":0}}
        """
        MockURLProtocol.handler = { _ in MockURLProtocol.ok(json) }
        let checks = try await MockURLProtocol.makeClient().healthChecks(orgId: "home").items
        let check = try XCTUnwrap(checks.first)
        XCTAssertEqual(check.id, 5)
        XCTAssertEqual(check.health, "unhealthy")
        XCTAssertEqual(check.displayTarget, "https://10.0.0.9:5000/health")
        XCTAssertFalse(check.isTargetCheck)

        MockURLProtocol.handler = { _ in MockURLProtocol.ok(#"{"targetHealthCheckId":6}"#) }
        let id = try await MockURLProtocol.makeClient().createHealthCheck(
            orgId: "home",
            HealthCheckBody(name: "Router", siteId: 1, hcEnabled: true, hcMode: .ping, hcHostname: "10.0.0.1"))
        XCTAssertEqual(id, 6)
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/v1/org/home/health-check")
        let sent = try sentJSON()
        XCTAssertEqual(sent["hcMode"] as? String, "ping")
        XCTAssertNil(sent["hcPort"], "Unset fields must be omitted")
    }

    // MARK: Alert rules

    func testAlertRulesDecodeAndCreate() async throws {
        let json = """
        {"alertRules":[{"alertRuleId":3,"orgId":"home","name":"Site down","eventType":"site_offline","enabled":true,
          "cooldownSeconds":300,"lastTriggeredAt":1730000000000,"createdAt":1,"updatedAt":2,
          "siteIds":[1,2],"healthCheckIds":[],"resourceIds":[]}],
         "pagination":{"total":1,"limit":1000,"offset":0}}
        """
        MockURLProtocol.handler = { _ in MockURLProtocol.ok(json) }
        let rules = try await MockURLProtocol.makeClient().alertRules(orgId: "home").items
        let rule = try XCTUnwrap(rules.first)
        XCTAssertEqual(rule.eventType, .siteOffline)
        XCTAssertEqual(rule.eventType?.source, .site)
        XCTAssertEqual(rule.siteIds, [1, 2])
        XCTAssertEqual(rule.lastTriggeredAt, Date(timeIntervalSince1970: 1_730_000_000))

        MockURLProtocol.handler = { _ in MockURLProtocol.ok(#"{"alertRuleId":4}"#) }
        let body = AlertRuleBody(name: "Down", eventType: .siteOffline, siteIds: [1], emails: ["ops@example.com"])
        XCTAssertNil(body.validationError)
        let id = try await MockURLProtocol.makeClient().createAlertRule(orgId: "home", body)
        XCTAssertEqual(id, 4)
        let sent = try sentJSON()
        XCTAssertEqual(sent["eventType"] as? String, "site_offline")
        XCTAssertNil(sent["healthCheckIds"], "Other sources must not be sent")
    }

    func testAlertRuleValidation() {
        XCTAssertNotNil(AlertRuleBody(name: "x", eventType: .resourceUnhealthy).validationError)
        XCTAssertNil(AlertRuleBody(name: "x", eventType: .resourceUnhealthy, allResources: true).validationError)
        XCTAssertNotNil(AlertRuleBody(name: "x", eventType: .siteOffline, siteIds: [1], resourceIds: [2]).validationError)
        XCTAssertTrue(AlertRuleBody(name: "x", eventType: .siteOffline, allSites: true).hasNoRecipients)
    }
}
