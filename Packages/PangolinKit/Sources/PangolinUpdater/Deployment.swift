import Foundation

/// How Docker commands are run on the server.
public enum DockerAccess: String, Sendable, Codable {
    /// User is root or in the `docker` group.
    case direct
    /// Commands run through `sudo -n` (passwordless sudo).
    case sudo

    /// Wraps a shell script so it runs with the right privileges.
    public func wrap(_ script: String) -> String {
        switch self {
        case .direct: "sh -c \(Shell.quote(script))"
        case .sudo: "sudo -n sh -c \(Shell.quote(script))"
        }
    }
}

/// A running container as reported by `docker ps`.
public struct DockerContainer: Sendable, Hashable {
    public let name: String
    public let image: String
    public let state: String
    public let project: String?
    public let workingDir: String?
    public let configFiles: [String]
    public let service: String?
}

/// The Pangolin compose deployment found on the server.
public struct PangolinDeployment: Sendable, Hashable {
    public let access: DockerAccess
    public let container: DockerContainer
    /// All containers of the same compose project.
    public let projectContainers: [DockerContainer]

    public var project: String { container.project ?? "" }
    public var workingDir: String { container.workingDir ?? "" }
    /// Primary compose file (absolute path).
    public var composeFile: String {
        container.configFiles.first ?? (workingDir as NSString).appendingPathComponent("docker-compose.yml")
    }
    public var runningImage: ImageReference? { ImageReference(container.image) }
}

public enum DeploymentError: Error, Sendable, Equatable, LocalizedError {
    case dockerUnavailable(String)
    case pangolinNotFound([String])
    case notComposeManaged(String)

    public var errorDescription: String? {
        switch self {
        case .dockerUnavailable(let detail):
            "Docker ist für diesen Benutzer nicht nutzbar – weder direkt noch per „sudo -n“. Lösung: Benutzer in die Gruppe „docker“ aufnehmen oder eine NOPASSWD-Regel für sudo einrichten.\n\(detail)"
        case .pangolinNotFound(let names):
            "Kein Pangolin-Container gefunden (Image fosrl/pangolin). Gefundene Container: \(names.isEmpty ? "keine" : names.joined(separator: ", "))"
        case .notComposeManaged(let name):
            "Der Container „\(name)“ wurde nicht mit Docker Compose gestartet – der Updater benötigt die docker-compose.yml."
        }
    }
}

/// Commands and parsers for finding the deployment.
public enum DeploymentDiscovery {
    static let separator = "|#|"

    /// Checks whether docker works directly or via sudo. Prints `PA_ACCESS=direct|sudo|none`.
    public static let accessProbeCommand = """
    if docker info --format '{{.ServerVersion}}' >/dev/null 2>&1; then echo PA_ACCESS=direct; \
    elif sudo -n docker info --format '{{.ServerVersion}}' >/dev/null 2>&1; then echo PA_ACCESS=sudo; \
    else echo PA_ACCESS=none; docker info 2>&1 | tail -3; fi
    """

    public static func parseAccess(_ output: String) throws -> DockerAccess {
        if output.contains("PA_ACCESS=direct") { return .direct }
        if output.contains("PA_ACCESS=sudo") { return .sudo }
        let detail = output.replacingOccurrences(of: "PA_ACCESS=none", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        throw DeploymentError.dockerUnavailable(detail)
    }

    /// Lists all containers with their compose labels.
    public static var listContainersScript: String {
        let fields = [
            "{{.Names}}", "{{.Image}}", "{{.State}}",
            "{{.Label \"com.docker.compose.project\"}}",
            "{{.Label \"com.docker.compose.project.working_dir\"}}",
            "{{.Label \"com.docker.compose.project.config_files\"}}",
            "{{.Label \"com.docker.compose.service\"}}"
        ].joined(separator: separator)
        return "docker ps -a --format \(Shell.quote(fields))"
    }

    public static func parseContainers(_ output: String) -> [DockerContainer] {
        output.split(separator: "\n").compactMap { line in
            let f = line.components(separatedBy: separator)
            guard f.count >= 7 else { return nil }
            func value(_ s: String) -> String? { s.isEmpty || s == "<no value>" ? nil : s }
            return DockerContainer(
                name: f[0], image: f[1], state: f[2],
                project: value(f[3]), workingDir: value(f[4]),
                configFiles: (value(f[5]) ?? "").split(separator: ",").map(String.init),
                service: value(f[6]))
        }
    }

    /// Picks the Pangolin container (prefers running ones).
    public static func findDeployment(containers: [DockerContainer], access: DockerAccess) throws -> PangolinDeployment {
        let candidates = containers.filter { ImageReference($0.image)?.repository.hasSuffix("fosrl/pangolin") == true }
        guard let pangolin = candidates.first(where: { $0.state == "running" }) ?? candidates.first else {
            throw DeploymentError.pangolinNotFound(containers.map(\.name))
        }
        guard pangolin.project != nil, pangolin.workingDir != nil else {
            throw DeploymentError.notComposeManaged(pangolin.name)
        }
        let siblings = containers.filter { $0.project == pangolin.project }
        return PangolinDeployment(access: access, container: pangolin, projectContainers: siblings)
    }

    /// Reads the compose file.
    public static func readComposeScript(_ deployment: PangolinDeployment) -> String {
        "cat -- \(Shell.quote(deployment.composeFile))"
    }

    /// Lists earlier backups created by the app (newest first).
    public static func listBackupsScript(_ deployment: PangolinDeployment) -> String {
        "cd -- \(Shell.quote(deployment.workingDir)) && ls -1d \(UpdateScript.backupRoot)/*/ 2>/dev/null | sort -r | head -20"
    }
}

/// POSIX shell helpers.
public enum Shell {
    /// Single-quotes a value for /bin/sh.
    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
