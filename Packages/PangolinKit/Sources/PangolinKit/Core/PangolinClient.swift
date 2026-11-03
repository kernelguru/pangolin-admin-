import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Connection settings for a Pangolin Integration API.
public struct PangolinConfiguration: Sendable, Equatable {
    /// Base URL of the Integration API **including** `/v1`, e.g. `https://api.example.com/v1`.
    public var baseURL: URL
    /// The API key (`Authorization: Bearer …`). Load it from the Keychain, never hard-code it.
    public var apiKey: String
    /// Request timeout in seconds.
    public var timeout: TimeInterval

    public init(baseURL: URL, apiKey: String, timeout: TimeInterval = 20) {
        self.baseURL = PangolinConfiguration.normalize(baseURL)
        self.apiKey = apiKey
        self.timeout = timeout
    }

    /// Accepts `https://api.example.com`, `https://api.example.com/` or `…/v1` and
    /// always returns `…/v1` without a trailing slash.
    public static func normalize(_ url: URL) -> URL {
        var string = url.absoluteString
        while string.hasSuffix("/") { string.removeLast() }
        if !string.lowercased().hasSuffix("/v1") { string += "/v1" }
        return URL(string: string) ?? url
    }
}

public enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
}

/// Client for the Pangolin Integration API (`/v1`).
///
/// All methods are `async throws` and throw `PangolinError`.
/// Endpoints are grouped in extensions (`PangolinClient+Sites.swift`, …).
public final class PangolinClient: Sendable {
    public let configuration: PangolinConfiguration
    private let session: URLSession

    public init(configuration: PangolinConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    // MARK: - Request building

    func makeURL(_ path: [String], query: [URLQueryItem] = []) throws -> URL {
        let encodedPath = path
            .map { $0.addingPercentEncoding(withAllowedCharacters: .pangolinPathSegment) ?? $0 }
            .joined(separator: "/")
        let base = configuration.baseURL.absoluteString
        guard var components = URLComponents(string: base + "/" + encodedPath) else {
            throw PangolinError.invalidURL(base)
        }
        let filtered = query.filter { $0.value != nil }
        if !filtered.isEmpty { components.queryItems = filtered }
        guard let url = components.url else { throw PangolinError.invalidURL(base) }
        return url
    }

    func makeRequest(_ method: HTTPMethod, _ path: [String], query: [URLQueryItem] = [],
                     body: (any Encodable)? = nil) throws -> URLRequest {
        var request = URLRequest(url: try makeURL(path, query: query))
        request.httpMethod = method.rawValue
        request.timeoutInterval = configuration.timeout
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw PangolinError.decoding("Request body: \(error)")
            }
        } else if method == .post || method == .put {
            // Pangolin's validators expect a JSON object for POST/PUT even when no fields are sent.
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
        }
        return request
    }

    // MARK: - Sending

    /// Sends a request and decodes `data` as `T`.
    func send<T: Decodable>(_ method: HTTPMethod, _ path: [String], query: [URLQueryItem] = [],
                            body: (any Encodable)? = nil, as type: T.Type = T.self,
                            userInfo: [CodingUserInfoKey: any Sendable] = [:]) async throws -> T {
        let request = try makeRequest(method, path, query: query, body: body)
        let (data, response) = try await perform(request)
        try Self.validate(response: response, data: data)

        let decoder = JSONDecoder()
        decoder.userInfo = userInfo
        let envelope: Envelope<T>
        do {
            envelope = try decoder.decode(Envelope<T>.self, from: data)
        } catch {
            throw PangolinError.decoding(Self.describe(error))
        }
        if envelope.success == false {
            throw PangolinError.server(status: envelope.status ?? 200, message: envelope.message ?? "")
        }
        if let payload = envelope.data { return payload }
        if T.self == EmptyPayload.self, let empty = EmptyPayload() as? T { return empty }
        throw PangolinError.emptyResponse(message: envelope.message ?? "")
    }

    /// Sends a request where only success matters.
    func sendAction(_ method: HTTPMethod, _ path: [String], query: [URLQueryItem] = [],
                    body: (any Encodable)? = nil) async throws {
        _ = try await send(method, path, query: query, body: body, as: EmptyPayload.self)
    }

    /// Fetches one page of a list endpoint, where items live under `data[key]`.
    func sendList<Item: Decodable & Sendable>(_ path: [String], key: String,
                                              query: [URLQueryItem] = [],
                                              as type: Item.Type = Item.self) async throws -> Page<Item> {
        let payload = try await send(.get, path, query: query, as: ListPayload<Item>.self,
                                     userInfo: [.pangolinListKey: key])
        return Page(items: payload.items, pagination: payload.pagination)
    }

    /// Fetches the raw bytes of an endpoint (used for CSV exports).
    func sendRaw(_ method: HTTPMethod, _ path: [String], query: [URLQueryItem] = []) async throws -> Data {
        let request = try makeRequest(method, path, query: query)
        let (data, response) = try await perform(request)
        try Self.validate(response: response, data: data)
        return data
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            throw PangolinError.transport(error.localizedDescription)
        } catch {
            throw PangolinError.transport(String(describing: error))
        }
    }

    static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PangolinError.transport("Keine HTTP-Antwort")
        }
        guard !(200..<300).contains(http.statusCode) else { return }

        let message = (try? JSONDecoder().decode(Envelope<EmptyPayload>.self, from: data))?.message
            ?? String(data: data.prefix(300), encoding: .utf8)
            ?? ""
        switch http.statusCode {
        case 401: throw PangolinError.unauthorized(message: message)
        case 403: throw PangolinError.forbidden(message: message)
        case 404: throw PangolinError.notFound(message: message)
        case 429: throw PangolinError.rateLimited(message: message)
        default: throw PangolinError.server(status: http.statusCode, message: message)
        }
    }

    static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return String(describing: error) }
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch error {
        case .typeMismatch(let type, let ctx): return "Typ \(type) erwartet bei \(path(ctx))"
        case .valueNotFound(let type, let ctx): return "Wert \(type) fehlt bei \(path(ctx))"
        case .keyNotFound(let key, let ctx): return "Feld \(key.stringValue) fehlt bei \(path(ctx))"
        case .dataCorrupted(let ctx): return "Ungültige Daten bei \(path(ctx)): \(ctx.debugDescription)"
        @unknown default: return String(describing: error)
        }
    }
}

// MARK: - Query helpers

extension URLQueryItem {
    static func int(_ name: String, _ value: Int?) -> URLQueryItem {
        URLQueryItem(name: name, value: value.map(String.init))
    }
    static func bool(_ name: String, _ value: Bool?) -> URLQueryItem {
        URLQueryItem(name: name, value: value.map { $0 ? "true" : "false" })
    }
    static func string(_ name: String, _ value: String?) -> URLQueryItem {
        URLQueryItem(name: name, value: (value?.isEmpty ?? true) ? nil : value)
    }
    static func date(_ name: String, _ value: Date?) -> URLQueryItem {
        URLQueryItem(name: name, value: value.map { ISO8601DateFormatter().string(from: $0) })
    }
}

extension CharacterSet {
    /// Characters allowed inside a single path segment (no `/`).
    static let pangolinPathSegment: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/?#")
        return set
    }()
}

/// Sorting order for list endpoints.
public enum SortOrder: String, Sendable { case asc, desc }

/// Pagination input for `page`/`pageSize` endpoints.
public struct PageRequest: Sendable, Equatable {
    public var page: Int
    public var pageSize: Int
    public init(page: Int = 1, pageSize: Int = 100) {
        self.page = page
        self.pageSize = pageSize
    }
}

extension PangolinClient {
    /// Fetches consecutive pages until everything is loaded or `maxPages` is reached.
    public func fetchAll<Item: Sendable>(pageSize: Int = 100, maxPages: Int = 20,
                                         _ fetch: (PageRequest) async throws -> Page<Item>) async throws -> [Item] {
        var all: [Item] = []
        var page = 1
        while page <= maxPages {
            let result = try await fetch(PageRequest(page: page, pageSize: pageSize))
            all.append(contentsOf: result.items)
            let total = result.pagination?.total ?? all.count
            if result.items.isEmpty || all.count >= total || result.items.count < pageSize { break }
            page += 1
        }
        return all
    }
}
