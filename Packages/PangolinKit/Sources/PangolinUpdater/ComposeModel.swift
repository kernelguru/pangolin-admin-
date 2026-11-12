import Foundation

/// A Docker image reference such as `docker.io/fosrl/pangolin:ee-1.12.3`.
public struct ImageReference: Sendable, Hashable, CustomStringConvertible {
    /// As written in the compose file.
    public let raw: String
    /// `docker.io`, `ghcr.io`, … (`nil` = Docker Hub default).
    public let registry: String?
    /// `fosrl/pangolin`, `traefik`, `crowdsecurity/crowdsec`.
    public let repository: String
    /// `ee-1.12.3`, `v3.7.16`, `18`, `latest` (nil if no tag).
    public let tag: String?

    public init?(_ raw: String) {
        var value = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
        guard !value.isEmpty, !value.contains("$") else { return nil } // skip ${VAR} images
        self.raw = value
        if let at = value.firstIndex(of: "@") { value = String(value[..<at]) } // drop digest
        var tag: String?
        if let colon = value.lastIndex(of: ":"), !value[colon...].contains("/") {
            tag = String(value[value.index(after: colon)...])
            value = String(value[..<colon])
        }
        var parts = value.split(separator: "/").map(String.init)
        var registry: String?
        if parts.count > 1, parts[0].contains(".") || parts[0].contains(":") || parts[0] == "localhost" {
            registry = parts.removeFirst()
        }
        guard !parts.isEmpty else { return nil }
        self.registry = registry
        self.repository = parts.joined(separator: "/")
        self.tag = tag
    }

    public var description: String { raw }

    /// `true` for Docker Hub images (no registry or docker.io).
    public var isDockerHub: Bool { registry == nil || registry == "docker.io" || registry == "index.docker.io" }

    /// Docker Hub namespace/name (`library/traefik` for official images).
    public var dockerHubPath: String { repository.contains("/") ? repository : "library/\(repository)" }

    /// Tag split into prefix, semantic version and suffix – e.g. `ee-1.12.3` → ("ee-", 1.12.3, "").
    public var versionedTag: VersionedTag? { tag.flatMap(VersionedTag.init) }

    /// Same reference with another tag, preserving registry and repository spelling.
    public func with(tag newTag: String) -> String {
        let base: String
        if let tag, raw.hasSuffix(":" + tag) {
            base = String(raw.dropLast(tag.count + 1))
        } else {
            base = raw
        }
        return base + ":" + newTag
    }
}

/// A tag containing a semantic version, keeping everything around it.
public struct VersionedTag: Sendable, Hashable {
    public let prefix: String
    public let hasV: Bool
    public let version: SemanticVersion
    public let suffix: String

    public init?(_ tag: String) {
        guard let regex = try? NSRegularExpression(pattern: #"^(.*?)(v?)(\d+)\.(\d+)(?:\.(\d+))?(.*)$"#),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        func group(_ i: Int) -> String? {
            guard let range = Range(match.range(at: i), in: tag) else { return nil }
            return String(tag[range])
        }
        guard let major = group(3).flatMap(Int.init), let minor = group(4).flatMap(Int.init) else { return nil }
        prefix = group(1) ?? ""
        hasV = group(2) == "v"
        version = SemanticVersion(major: major, minor: minor, patch: group(5).flatMap(Int.init) ?? 0,
                                  componentCount: group(5) == nil ? 2 : 3)
        suffix = group(6) ?? ""
    }

    /// Builds the tag for another version in the same style (`ee-` prefix, `v`, suffix).
    public func tag(for newVersion: SemanticVersion) -> String {
        prefix + (hasV ? "v" : "") + newVersion.string(components: version.componentCount) + suffix
    }
}

public struct SemanticVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// 2 for `18.1`, 3 for `1.12.3`.
    public let componentCount: Int

    public init(major: Int, minor: Int, patch: Int, componentCount: Int = 3) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.componentCount = componentCount
    }

    /// Parses `1.12.3`, `v3.7.16`; ignores pre-release suffixes like `-rc.1` (returns nil for those).
    public init?(_ string: String) {
        var value = string.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
        let parts = value.split(separator: ".")
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0.allSatisfy(\.isNumber) && !$0.isEmpty }),
              let major = Int(parts[0]), let minor = Int(parts[1]) else { return nil }
        self.init(major: major, minor: minor, patch: parts.count == 3 ? Int(parts[2]) ?? 0 : 0,
                  componentCount: parts.count)
    }

    public func string(components: Int = 3) -> String {
        components == 2 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }

    public var description: String { string(components: componentCount) }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) == (rhs.major, rhs.minor, rhs.patch)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(major); hasher.combine(minor); hasher.combine(patch)
    }
}

/// One `image:` line in a compose file.
public struct ComposeImage: Sendable, Hashable, Identifiable {
    public var id: Int { lineNumber }
    /// 1-based line number in the compose file.
    public let lineNumber: Int
    public let service: String?
    public let image: ImageReference
}

/// Minimal compose reader: finds `image:` lines and the service they belong to.
/// Deliberately line-based so edits touch exactly one line and keep comments/formatting.
public enum ComposeFile {
    public static func images(in text: String) -> [ComposeImage] {
        var result: [ComposeImage] = []
        var inServices = false
        var serviceIndent: Int?
        var currentService: String?

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.replacingOccurrences(of: "\t", with: "  ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = line.prefix { $0 == " " }.count

            if indent == 0 {
                inServices = trimmed.hasPrefix("services:")
                serviceIndent = nil
                currentService = nil
                continue
            }
            guard inServices else { continue }

            if serviceIndent == nil { serviceIndent = indent }
            if indent == serviceIndent, trimmed.hasSuffix(":") {
                currentService = String(trimmed.dropLast()).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                continue
            }
            if trimmed.hasPrefix("image:") {
                var value = String(trimmed.dropFirst("image:".count))
                if let hash = value.range(of: " #") { value = String(value[..<hash.lowerBound]) }
                if let reference = ImageReference(value) {
                    result.append(ComposeImage(lineNumber: index + 1, service: currentService, image: reference))
                }
            }
        }
        return result
    }
}
