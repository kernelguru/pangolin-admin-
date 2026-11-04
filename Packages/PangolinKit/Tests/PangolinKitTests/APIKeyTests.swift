import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PangolinKit

final class APIKeyTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    func testSanitizeRemovesPasteArtifacts() {
        XCTAssertEqual(PangolinConfiguration.sanitize(apiKey: "  abc123.s3cr3t\n"), "abc123.s3cr3t")
        XCTAssertEqual(PangolinConfiguration.sanitize(apiKey: "Bearer abc123.s3cr3t"), "abc123.s3cr3t")
        XCTAssertEqual(PangolinConfiguration.sanitize(apiKey: "\"abc123.s3cr3t\""), "abc123.s3cr3t")
        XCTAssertEqual(PangolinConfiguration.sanitize(apiKey: "abc123.s3c\nr3t"), "abc123.s3cr3t")
    }

    func testConfigurationSanitizesKeyForHeader() async throws {
        MockURLProtocol.handler = { _ in MockURLProtocol.ok(#"{"org":{"orgId":"o","name":"O"}}"#) }
        _ = try await MockURLProtocol.makeClient(key: " id.secret \n").organization("o")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer id.secret")
    }

    func testFormatProblem() {
        XCTAssertNil(PangolinConfiguration.formatProblem(apiKey: "abc.def"))
        XCTAssertNil(PangolinConfiguration.formatProblem(apiKey: ""))
        XCTAssertNotNil(PangolinConfiguration.formatProblem(apiKey: "abcdef"))
        XCTAssertNotNil(PangolinConfiguration.formatProblem(apiKey: "abc."))
        XCTAssertNotNil(PangolinConfiguration.formatProblem(apiKey: "a.b.c"))
    }

    func testURLProblem() {
        XCTAssertNil(PangolinConfiguration.urlProblem(URL(string: "https://api.example.com/v1")!))
        XCTAssertNotNil(PangolinConfiguration.urlProblem(URL(string: "https://pangolin.example.com/api/v1")!))
        XCTAssertNotNil(PangolinConfiguration.urlProblem(URL(string: "http://10.0.0.2:3001")!))
        XCTAssertNil(PangolinConfiguration.urlProblem(URL(string: "http://10.0.0.2:3003")!))
    }

    func testUnauthorizedExplanations() {
        let invalid = PangolinError.unauthorized(message: "Invalid API key").localizedDescription
        XCTAssertTrue(invalid.contains("ID.Geheimnis"), invalid)
        let missing = PangolinError.unauthorized(message: "API key required").localizedDescription
        XCTAssertTrue(missing.contains("Weiterleitung"), missing)
        let dashboard = PangolinError.unauthorized(message: "User not authenticated").localizedDescription
        XCTAssertTrue(dashboard.contains("Dashboard-API"), dashboard)
    }
}
