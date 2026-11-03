import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PangolinKit

/// Intercepts requests and answers with canned responses.
final class MockURLProtocol: URLProtocol {
    struct Stub {
        var status: Int
        var body: String
    }

    nonisolated(unsafe) static var handler: ((URLRequest) -> Stub)?
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequest = request
        MockURLProtocol.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let stub = MockURLProtocol.handler?(request) ?? Stub(status: 500, body: "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    static func makeClient(baseURL: String = "https://api.example.com/v1", key: String = "test-key") -> PangolinClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return PangolinClient(configuration: PangolinConfiguration(baseURL: URL(string: baseURL)!, apiKey: key),
                              session: session)
    }

    static func ok(_ data: String) -> Stub {
        Stub(status: 200, body: #"{"data":\#(data),"success":true,"error":false,"message":"ok","status":200}"#)
    }
}
