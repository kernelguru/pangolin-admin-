import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PangolinKit

final class PangolinClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.lastBody = nil
        super.tearDown()
    }

    // MARK: Configuration

    func testBaseURLNormalization() {
        for input in ["https://api.example.com", "https://api.example.com/", "https://api.example.com/v1",
                      "https://api.example.com/v1/"] {
            XCTAssertEqual(PangolinConfiguration.normalize(URL(string: input)!).absoluteString,
                           "https://api.example.com/v1", input)
        }
    }

    // MARK: Request building

    func testAuthorizationHeaderAndPathEncoding() async throws {
        MockURLProtocol.handler = { _ in MockURLProtocol.ok(#"{"org":{"orgId":"my org","name":"Home"}}"#) }
        let client = MockURLProtocol.makeClient(key: "abc.123")

        let org = try await client.organization("my org")

        XCTAssertEqual(org.name, "Home")
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc.123")
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/org/my%20org")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testSiteListDecodingAndQuery() async throws {
        // Shape taken from server/routers/site/listSites.ts
        let json = """
        {"sites":[
          {"siteId":1,"niceId":"home-lab","name":"Home Lab","pubKey":null,"subnet":"100.89.128.4/30",
           "megabytesIn":120.5,"megabytesOut":"80","orgName":"Home","type":"newt","online":1,
           "address":null,"newtVersion":"1.6.0","newtUpdateAvailable":true,"exitNodeId":1,
           "exitNodeName":"main","resourceCount":4,"status":"approved",
           "labels":[{"labelId":3,"name":"prod","color":"#ff0000"}]},
          {"siteId":2,"niceId":"local","name":"Local","type":"local","status":"pending"}
        ],"pagination":{"total":2,"pageSize":100,"page":1}}
        """
        MockURLProtocol.handler = { _ in MockURLProtocol.ok(json) }
        let client = MockURLProtocol.makeClient()

        let page = try await client.sites(orgId: "home", query: SiteQuery(search: "lab", online: true))

        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.total, 2)
        let first = page.items[0]
        XCTAssertEqual(first.online, true, "Integer 1 must decode as true")
        XCTAssertEqual(first.megabytesOut, 80, "String numbers must decode")
        XCTAssertEqual(first.totalMegabytes, 200.5)
        XCTAssertEqual(first.labels.first?.name, "prod")
        XCTAssertNil(page.items[1].online)
        XCTAssertTrue(page.items[1].isPending)
        XCTAssertTrue(page.items[1].isLocal)

        let url = try XCTUnwrap(MockURLProtocol.lastRequest?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(url.path, "/v1/org/home/sites")
        XCTAssertTrue(items.contains(URLQueryItem(name: "query", value: "lab")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "online", value: "true")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "pageSize", value: "100")))
        XCTAssertFalse(items.contains { $0.name == "status" }, "nil filters must not be sent")
    }

    func testResourceListDecoding() async throws {
        // Shape taken from server/routers/resource/listResources.ts
        let json = """
        {"resources":[{"resourceId":7,"niceId":"grafana","name":"Grafana","ssl":true,
          "fullDomain":"grafana.example.com","passwordId":null,"sso":1,"pincodeId":null,"whitelist":0,
          "mtls":false,"proxyPort":null,"enabled":true,"domainId":"d1","headerAuthId":null,"wildcard":false,
          "health":"degraded","mode":"http",
          "targets":[{"targetId":11,"ip":"10.0.0.5","port":3000,"enabled":true,"healthStatus":"healthy","siteName":"Home Lab"}],
          "sites":[{"siteId":1,"siteName":"Home Lab","siteNiceId":"home-lab","online":true}],
          "labels":[]}],
         "pagination":{"total":1,"pageSize":100,"page":1}}
        """
        MockURLProtocol.handler = { _ in MockURLProtocol.ok(json) }
        let client = MockURLProtocol.makeClient()

        let resources = try await client.allResources(orgId: "home")

        XCTAssertEqual(resources.count, 1)
        let r = resources[0]
        XCTAssertEqual(r.health, .degraded)
        XCTAssertEqual(r.sso, true)
        XCTAssertTrue(r.isProtected)
        XCTAssertEqual(r.displayAddress, "https://grafana.example.com")
        XCTAssertEqual(r.targets.first?.port, 3000)
        XCTAssertEqual(r.sites.first?.online, true)
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/v1/org/home/public-resources")
    }

    func testFetchAllPagesThroughResults() async throws {
        nonisolated(unsafe) var calls = 0
        MockURLProtocol.handler = { request in
            calls += 1
            let page = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "page" }?.value ?? "1"
            let id = Int(page)!
            return MockURLProtocol.ok(#"{"clients":[{"clientId":\#(id),"name":"c\#(id)"}],"pagination":{"total":3,"page":\#(id),"pageSize":1}}"#)
        }
        let client = MockURLProtocol.makeClient()

        let all = try await client.fetchAll(pageSize: 1) { try await client.clients(orgId: "o", page: $0) }

        XCTAssertEqual(all.map(\.clientId), [1, 2, 3])
        XCTAssertEqual(calls, 3)
    }

    func testUsersDecodeRoles() async throws {
        let json = """
        {"users":[{"id":"u1","email":"a@b.de","emailVerified":true,"dateCreated":"2025-01-01T00:00:00.000Z",
          "orgId":"home","username":"anna","name":"Anna","type":"internal","isOwner":true,"idpName":null,
          "idpId":null,"twoFactorEnabled":false,"roles":[{"roleId":1,"roleName":"Admin"}]}],
         "pagination":{"total":1,"page":1,"pageSize":100}}
        """
        MockURLProtocol.handler = { _ in MockURLProtocol.ok(json) }
        let users = try await MockURLProtocol.makeClient().users(orgId: "home").items
        XCTAssertEqual(users.first?.displayName, "Anna")
        XCTAssertEqual(users.first?.roles.first?.roleName, "Admin")
        XCTAssertEqual(users.first?.isOwner, true)
    }

    func testRequestLogDecodingAndTimeRange() async throws {
        let json = """
        {"log":[{"timestamp":1730000000,"action":true,"reason":100,"orgId":"home","actorType":"user",
          "actor":"anna","resourceId":7,"resourceName":"Grafana","ip":"1.2.3.4","location":"DE",
          "host":"grafana.example.com","path":"/login","method":"GET","scheme":"https","tls":true}],
         "pagination":{"total":1,"limit":100,"offset":0},
         "filterAttributes":{"actors":[],"resources":[],"locations":[],"hosts":[],"paths":[]}}
        """
        MockURLProtocol.handler = { _ in MockURLProtocol.ok(json) }
        let start = Date(timeIntervalSince1970: 1_729_900_000)
        let logs = try await MockURLProtocol.makeClient()
            .requestLogs(orgId: "home", LogQuery(start: start, end: nil, limit: 50))

        let entry = try XCTUnwrap(logs.items.first)
        XCTAssertTrue(entry.allowed)
        XCTAssertEqual(entry.timestamp, Date(timeIntervalSince1970: 1_730_000_000))
        XCTAssertEqual(entry.url, "https://grafana.example.com/login")

        let items = URLComponents(url: MockURLProtocol.lastRequest!.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "timeStart" }?.value, "2024-10-25T23:46:40Z")
        XCTAssertEqual(items.first { $0.name == "limit" }?.value, "50")
        XCTAssertFalse(items.contains { $0.name == "timeEnd" })
    }

    func testInvitationTimestampsInMilliseconds() async throws {
        let json = #"{"invitations":[{"inviteId":"i1","email":"x@y.de","expiresAt":1730000000000,"roles":[]}],"pagination":{"total":1,"limit":1000,"offset":0}}"#
        MockURLProtocol.handler = { _ in MockURLProtocol.ok(json) }
        let invite = try await MockURLProtocol.makeClient().invitations(orgId: "home").items.first
        XCTAssertEqual(invite?.expiresAt, Date(timeIntervalSince1970: 1_730_000_000))
    }

    // MARK: Actions & bodies

    func testUpdateResourceSendsOnlySetFields() async throws {
        MockURLProtocol.handler = { _ in MockURLProtocol.ok("{}") }
        try await MockURLProtocol.makeClient().setResourceEnabled(7, enabled: false)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v1/public-resource/7")
        let body = try XCTUnwrap(MockURLProtocol.lastBody)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(object?.count, 1)
        XCTAssertEqual(object?["enabled"] as? Bool, false)
    }

    func testPostWithoutBodySendsEmptyObject() async throws {
        MockURLProtocol.handler = { _ in MockURLProtocol.ok("null") }
        try await MockURLProtocol.makeClient().restartSite(5)
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/v1/site/5/restart")
        XCTAssertEqual(MockURLProtocol.lastBody.flatMap { String(data: $0, encoding: .utf8) }, "{}")
    }

    func testInviteBodyClampsHours() async throws {
        MockURLProtocol.handler = { _ in MockURLProtocol.ok(#"{"inviteLink":"https://p.example.com/invite?token=x","expiresAt":1730000000000}"#) }
        let result = try await MockURLProtocol.makeClient()
            .invite(orgId: "home", CreateInviteBody(email: "x@y.de", roleIds: [2], validHours: 500))
        XCTAssertEqual(result.inviteLink, "https://p.example.com/invite?token=x")
        let object = try JSONSerialization.jsonObject(with: MockURLProtocol.lastBody!) as? [String: Any]
        XCTAssertEqual(object?["validHours"] as? Int, 168)
        XCTAssertEqual(object?["roleIds"] as? [Int], [2])
    }

    // MARK: Errors

    func testUnauthorizedError() async {
        MockURLProtocol.handler = { _ in
            .init(status: 401, body: #"{"data":null,"success":false,"error":true,"message":"Invalid API key","status":401}"#)
        }
        do {
            _ = try await MockURLProtocol.makeClient().organization("home")
            XCTFail("Expected error")
        } catch let error as PangolinError {
            XCTAssertEqual(error, .unauthorized(message: "Invalid API key"))
            XCTAssertEqual(error.statusCode, 401)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testForbiddenAndServerErrors() async {
        MockURLProtocol.handler = { _ in .init(status: 403, body: #"{"message":"Key does not have permission"}"#) }
        do {
            try await MockURLProtocol.makeClient().deleteSite(1)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? PangolinError, .forbidden(message: "Key does not have permission"))
        }

        MockURLProtocol.handler = { _ in .init(status: 502, body: "Bad Gateway") }
        do {
            try await MockURLProtocol.makeClient().deleteSite(1)
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? PangolinError, .server(status: 502, message: "Bad Gateway"))
        }
    }

    func testBrokenItemsAreSkippedNotFatal() async throws {
        // A target without required fields must not break the whole resource.
        let json = #"{"resources":[{"resourceId":1,"name":"A","targets":["oops",{"targetId":2,"ip":"x","port":1}]}],"pagination":{"total":1}}"#
        MockURLProtocol.handler = { _ in MockURLProtocol.ok(json) }
        let page = try await MockURLProtocol.makeClient().resources(orgId: "o")
        XCTAssertEqual(page.items.first?.targets.map(\.targetId), [2])
        XCTAssertEqual(page.items.first?.enabled, true)
    }

    // MARK: Secret store

    func testInMemorySecretStore() throws {
        let store = InMemorySecretStore()
        try store.save("secret", for: "a")
        XCTAssertEqual(try store.read("a"), "secret")
        try store.delete("a")
        XCTAssertNil(try store.read("a"))
    }
}
