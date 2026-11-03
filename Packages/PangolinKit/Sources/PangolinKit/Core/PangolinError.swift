import Foundation

/// Errors thrown by `PangolinClient`.
public enum PangolinError: Error, Sendable, Equatable {
    /// The configured base URL could not be combined with the request path.
    case invalidURL(String)
    /// The API key was rejected (HTTP 401).
    case unauthorized(message: String)
    /// The API key is valid but lacks the permission for this action (HTTP 403).
    case forbidden(message: String)
    /// The requested object does not exist (HTTP 404).
    case notFound(message: String)
    /// Too many requests (HTTP 429).
    case rateLimited(message: String)
    /// Any other non-2xx response from Pangolin.
    case server(status: Int, message: String)
    /// The response could not be decoded into the expected model.
    case decoding(String)
    /// Network or TLS problem before a response arrived.
    case transport(String)
    /// The server replied with `success: false` or without a `data` payload.
    case emptyResponse(message: String)

    /// HTTP status code, if the error came from an HTTP response.
    public var statusCode: Int? {
        switch self {
        case .unauthorized: 401
        case .forbidden: 403
        case .notFound: 404
        case .rateLimited: 429
        case .server(let status, _): status
        default: nil
        }
    }
}

extension PangolinError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            "Ungültige Server-URL: \(url)"
        case .unauthorized(let message):
            "API-Schlüssel ungültig oder abgelaufen. \(message)"
        case .forbidden(let message):
            "Dem API-Schlüssel fehlt die Berechtigung für diese Aktion. \(message)"
        case .notFound(let message):
            "Nicht gefunden. \(message)"
        case .rateLimited(let message):
            "Zu viele Anfragen – bitte kurz warten. \(message)"
        case .server(let status, let message):
            "Serverfehler (\(status)): \(message)"
        case .decoding(let detail):
            "Antwort des Servers konnte nicht gelesen werden: \(detail)"
        case .transport(let detail):
            "Netzwerkfehler: \(detail)"
        case .emptyResponse(let message):
            "Leere Antwort vom Server. \(message)"
        }
    }
}
