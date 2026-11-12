import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Looks up the newest released versions (GitHub) and checks tags on Docker Hub.
public struct ReleaseLookup: Sendable {
    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Newest non-prerelease version of a GitHub repository.
    public func latestVersion(_ source: VersionSource) async throws -> SemanticVersion {
        switch source {
        case .githubReleases(let owner, let repo):
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=20")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("pangolin-admin-ios", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            struct Release: Decodable {
                let tag_name: String
                let prerelease: Bool
                let draft: Bool
            }
            let releases = try JSONDecoder().decode([Release].self, from: data)
            let versions = releases
                .filter { !$0.prerelease && !$0.draft }
                .compactMap { SemanticVersion($0.tag_name) }
            guard let newest = versions.max() else { throw URLError(.cannotParseResponse) }
            return newest
        }
    }

    /// `true` if the tag exists on Docker Hub, `false` if not, `nil` if it could not be checked.
    public func dockerHubTagExists(_ image: ImageReference, tag: String) async -> Bool? {
        guard image.isDockerHub else { return nil }
        let path = image.dockerHubPath
        guard let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://hub.docker.com/v2/repositories/\(path)/tags/\(encoded)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (_, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        switch status {
        case 200: return true
        case 404: return false
        default: return nil
        }
    }

    /// Evaluates all images: looks up versions once per source and verifies new tags.
    public func evaluate(_ images: [ComposeImage]) async -> [ImageUpdate] {
        var latest: [VersionSource: SemanticVersion] = [:]
        for source in Set(images.compactMap { VersionSource.forImage($0.image) }) {
            if let version = try? await latestVersion(source) { latest[source] = version }
        }
        var updates: [ImageUpdate] = []
        for image in images {
            let version = VersionSource.forImage(image.image).flatMap { latest[$0] }
            var update = ImageUpdate.evaluate(image, latest: version)
            if case .retag(let tag, _) = update.action {
                update.tagVerified = await dockerHubTagExists(image.image, tag: tag)
            }
            updates.append(update)
        }
        return updates
    }
}
