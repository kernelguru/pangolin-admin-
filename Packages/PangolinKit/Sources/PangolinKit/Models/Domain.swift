import Foundation

/// A domain configured for an organization.
public struct Domain: Decodable, Sendable, Hashable, Identifiable {
    public var id: String { domainId }
    public var domainId: String
    public var baseDomain: String
    /// `ns`, `cname` or `wildcard`.
    public var type: String?
    public var verified: Bool?
    public var failed: Bool?
    public var tries: Int?
    public var configManaged: Bool?
    public var certResolver: String?
    public var preferWildcardCert: Bool?
    public var errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case domainId, baseDomain, type, verified, failed, tries, configManaged, certResolver,
             preferWildcardCert, errorMessage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        domainId = c.lenientString(.domainId) ?? ""
        baseDomain = c.lenientString(.baseDomain) ?? domainId
        type = c.lenientString(.type)
        verified = c.lenientBool(.verified)
        failed = c.lenientBool(.failed)
        tries = c.lenientInt(.tries)
        configManaged = c.lenientBool(.configManaged)
        certResolver = c.lenientString(.certResolver)
        preferWildcardCert = c.lenientBool(.preferWildcardCert)
        errorMessage = c.lenientString(.errorMessage)
    }
}
