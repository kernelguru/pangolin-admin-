import Foundation
import XCTest
@testable import PangolinUpdater

/// Rendered from Pangolin's installer template (enterprise, SQLite, Gerbil).
let sampleCompose = """
name: pangolin
services:
  pangolin:
    image: docker.io/fosrl/pangolin:ee-1.11.0
    container_name: pangolin
    restart: unless-stopped
    volumes:
      - ./config:/app/config
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/api/v1/"]

  gerbil:
    image: docker.io/fosrl/gerbil:1.2.1
    container_name: gerbil
    ports:
      - 443:443/udp # For http3 QUIC if desired

  traefik:
    image: docker.io/traefik:v3.7.16
    container_name: traefik
    volumes:
      - ./config/traefik:/etc/traefik:ro # Volume to store the Traefik configuration

  redis:
    image: "redis:8-trixie"
    container_name: redis

networks:
  default:
    driver: bridge
    name: pangolin_frontend
"""

final class ComposeParsingTests: XCTestCase {
    func testImageReferences() {
        let ee = ImageReference("docker.io/fosrl/pangolin:ee-1.11.0")!
        XCTAssertEqual(ee.registry, "docker.io")
        XCTAssertEqual(ee.repository, "fosrl/pangolin")
        XCTAssertEqual(ee.tag, "ee-1.11.0")
        XCTAssertEqual(ee.versionedTag?.prefix, "ee-")
        XCTAssertEqual(ee.versionedTag?.version, SemanticVersion("1.11.0"))
        XCTAssertEqual(ee.with(tag: "ee-1.12.3"), "docker.io/fosrl/pangolin:ee-1.12.3")

        let pg = ImageReference("fosrl/pangolin:ee-postgresql-1.11.0")!
        XCTAssertNil(pg.registry)
        XCTAssertEqual(pg.versionedTag?.prefix, "ee-postgresql-")
        XCTAssertEqual(pg.versionedTag?.tag(for: SemanticVersion("1.12.3")!), "ee-postgresql-1.12.3")

        let traefik = ImageReference("docker.io/traefik:v3.7.16")!
        XCTAssertEqual(traefik.repository, "traefik")
        XCTAssertEqual(traefik.dockerHubPath, "library/traefik")
        XCTAssertEqual(traefik.versionedTag?.tag(for: SemanticVersion("3.8.0")!), "v3.8.0")

        let local = ImageReference("localhost:5000/team/app:2.1")!
        XCTAssertEqual(local.registry, "localhost:5000")
        XCTAssertEqual(local.versionedTag?.tag(for: SemanticVersion("2.4.1")!), "2.4")

        XCTAssertNil(ImageReference("${PANGOLIN_IMAGE}"))
        XCTAssertNil(ImageReference("redis:latest")?.versionedTag)
    }

    func testComposeImages() {
        let images = ComposeFile.images(in: sampleCompose)
        XCTAssertEqual(images.map(\.service), ["pangolin", "gerbil", "traefik", "redis"])
        XCTAssertEqual(images.map(\.lineNumber), [4, 13, 19, 25])
        XCTAssertEqual(images[3].image.raw, "redis:8-trixie")
    }

    func testEvaluate() {
        let images = ComposeFile.images(in: sampleCompose)
        let pangolin = ImageUpdate.evaluate(images[0], latest: SemanticVersion("1.12.3"))
        XCTAssertEqual(pangolin.newReference, "docker.io/fosrl/pangolin:ee-1.12.3")
        XCTAssertFalse(pangolin.isMajorUpgrade)

        let gerbil = ImageUpdate.evaluate(images[1], latest: SemanticVersion("1.2.1"))
        XCTAssertEqual(gerbil.action, .upToDate)

        let traefik = ImageUpdate.evaluate(images[2], latest: SemanticVersion("v4.0.1"))
        XCTAssertTrue(traefik.isMajorUpgrade)
        XCTAssertEqual(traefik.newReference, "docker.io/traefik:v4.0.1")

        let redis = ImageUpdate.evaluate(images[3], latest: nil)
        XCTAssertEqual(redis.action, .pullOnly, "redis:8-trixie is a floating tag")

        XCTAssertNil(VersionSource.forImage(images[3].image))
        XCTAssertEqual(VersionSource.forImage(images[2].image), .githubReleases(owner: "traefik", repo: "traefik"))
    }

    func testSemanticVersionRejectsPrereleases() {
        XCTAssertNil(SemanticVersion("1.12.0-rc.1"))
        XCTAssertTrue(SemanticVersion("1.12.0")! > SemanticVersion("1.11.9")!)
        XCTAssertEqual(SemanticVersion("v3.7.16"), SemanticVersion("3.7.16"))
    }

    func testDockerPsParsingAndDiscovery() throws {
        let sep = "|#|"
        let output = [
            ["pangolin", "docker.io/fosrl/pangolin:ee-1.11.0", "running", "pangolin", "/root/pangolin", "/root/pangolin/docker-compose.yml", "pangolin"],
            ["gerbil", "docker.io/fosrl/gerbil:1.2.1", "running", "pangolin", "/root/pangolin", "/root/pangolin/docker-compose.yml", "gerbil"],
            ["other", "nginx:1", "running", "<no value>", "<no value>", "<no value>", "<no value>"]
        ].map { $0.joined(separator: sep) }.joined(separator: "\n")
        let containers = DeploymentDiscovery.parseContainers(output)
        XCTAssertEqual(containers.count, 3)
        XCTAssertNil(containers[2].project)

        let deployment = try DeploymentDiscovery.findDeployment(containers: containers, access: .sudo)
        XCTAssertEqual(deployment.composeFile, "/root/pangolin/docker-compose.yml")
        XCTAssertEqual(deployment.projectContainers.map(\.name), ["pangolin", "gerbil"])
        XCTAssertEqual(deployment.runningImage?.tag, "ee-1.11.0")

        XCTAssertThrowsError(try DeploymentDiscovery.findDeployment(containers: [containers[2]], access: .direct))
        XCTAssertEqual(try DeploymentDiscovery.parseAccess("PA_ACCESS=sudo\n"), .sudo)
        XCTAssertThrowsError(try DeploymentDiscovery.parseAccess("PA_ACCESS=none\npermission denied"))
    }

    func testShellQuote() {
        XCTAssertEqual(Shell.quote("a b"), "'a b'")
        XCTAssertEqual(Shell.quote("it's"), #"'it'\''s'"#)
        XCTAssertEqual(DockerAccess.sudo.wrap("echo 'x'"), #"sudo -n sh -c 'echo '\''x'\'''"#)
    }
}

/// Executes the generated scripts with /bin/sh against a fake `docker` binary.
final class UpdateScriptExecutionTests: XCTestCase {
    var root: URL!
    var stack: URL!
    var bin: URL!
    var log: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pa-\(UUID().uuidString)")
        stack = root.appendingPathComponent("pangolin stack") // space on purpose
        bin = root.appendingPathComponent("bin")
        log = root.appendingPathComponent("docker.log")
        try FileManager.default.createDirectory(at: stack.appendingPathComponent("config/db"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try sampleCompose.write(to: stack.appendingPathComponent("docker-compose.yml"), atomically: true, encoding: .utf8)
        try "sqlite-v1".write(to: stack.appendingPathComponent("config/db/db.sqlite"), atomically: true, encoding: .utf8)
        try "app: {}".write(to: stack.appendingPathComponent("config/config.yml"), atomically: true, encoding: .utf8)
        try installFakeDocker(failPull: false)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func installFakeDocker(failPull: Bool) throws {
        let script = """
        #!/bin/sh
        echo "$*" >> \(Shell.quote(log.path))
        case "$*" in
          "compose version") exit 0 ;;
          *" pull") \(failPull ? "echo 'manifest unknown' >&2; exit 1" : "echo pulled") ;;
          *" ps") echo "pangolin running" ;;
        esac
        exit 0
        """
        let url = bin.appendingPathComponent("docker")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private var deployment: PangolinDeployment {
        let file = stack.appendingPathComponent("docker-compose.yml").path
        let c = DockerContainer(name: "pangolin", image: "docker.io/fosrl/pangolin:ee-1.11.0", state: "running",
                                project: "pangolin", workingDir: stack.path, configFiles: [file], service: "pangolin")
        return PangolinDeployment(access: .direct, container: c, projectContainers: [c])
    }

    @discardableResult
    private func run(_ script: String) throws -> (output: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", DockerAccess.direct.wrap(script)]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = bin.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }

    private func compose() throws -> String {
        try String(contentsOf: stack.appendingPathComponent("docker-compose.yml"), encoding: .utf8)
    }

    private func plan() -> UpdatePlan {
        let images = ComposeFile.images(in: sampleCompose)
        let updates = [
            ImageUpdate.evaluate(images[0], latest: SemanticVersion("1.12.3")),
            ImageUpdate.evaluate(images[1], latest: SemanticVersion("1.3.0")),
            ImageUpdate.evaluate(images[2], latest: SemanticVersion("3.8.1")),
            ImageUpdate.evaluate(images[3], latest: nil)
        ]
        // Gerbil deliberately not selected.
        return UpdatePlan(deployment: deployment, updates: updates, selected: [4, 19, 25], postgresService: nil)
    }

    func testUpdateEditsOnlySelectedLinesAndBacksUp() throws {
        let (output, status) = try run(UpdateScript.update(plan()))
        XCTAssertEqual(status, 0, output)

        let updated = try compose()
        XCTAssertTrue(updated.contains("image: docker.io/fosrl/pangolin:ee-1.12.3"))
        XCTAssertTrue(updated.contains("image: docker.io/fosrl/gerbil:1.2.1"), "unselected image stays")
        XCTAssertTrue(updated.contains("image: docker.io/traefik:v3.8.1"))
        XCTAssertTrue(updated.contains(#"image: "redis:8-trixie""#))
        XCTAssertTrue(updated.contains("- 443:443/udp # For http3 QUIC if desired"), "comments untouched")
        XCTAssertEqual(updated.components(separatedBy: "\n").count, sampleCompose.components(separatedBy: "\n").count)

        let backup = try XCTUnwrap(output.components(separatedBy: "\n").first { $0.hasPrefix("PA_BACKUP=") }?
            .replacingOccurrences(of: "PA_BACKUP=", with: ""))
        XCTAssertEqual(try String(contentsOfFile: backup + "/docker-compose.yml", encoding: .utf8), sampleCompose)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup + "/config.tar.gz"))

        let steps = output.components(separatedBy: "\n").filter { $0.hasPrefix("PA_STEP=") }
        XCTAssertEqual(steps, ["PA_STEP=backup", "PA_STEP=edit", "PA_STEP=pull", "PA_STEP=stop",
                               "PA_STEP=snapshot", "PA_STEP=up", "PA_STEP=status", "PA_STEP=done"])

        let calls = try String(contentsOf: log, encoding: .utf8).components(separatedBy: "\n").filter { !$0.isEmpty }
        let file = stack.appendingPathComponent("docker-compose.yml").path
        XCTAssertTrue(calls.contains("compose -p pangolin -f \(file) pull"), calls.joined(separator: "\n"))
        XCTAssertTrue(calls.contains("compose -p pangolin -f \(file) up -d"))
        XCTAssertLessThan(calls.firstIndex(of: "compose -p pangolin -f \(file) pull")!,
                          calls.firstIndex(of: "compose -p pangolin -f \(file) stop")!, "pull before stop")
    }

    func testPullFailureRestoresComposeAndKeepsStackRunning() throws {
        try installFakeDocker(failPull: true)
        let (output, status) = try run(UpdateScript.update(plan()))
        XCTAssertEqual(status, 24, output)
        XCTAssertTrue(output.contains("PA_ERROR=Images konnten nicht geladen werden"))
        XCTAssertEqual(try compose(), sampleCompose)
        let calls = try String(contentsOf: log, encoding: .utf8)
        XCTAssertFalse(calls.contains(" stop"), "stack must not be stopped when pull fails")
    }

    func testChangedFileAbortsWithoutEdits() throws {
        let changed = sampleCompose.replacingOccurrences(of: "ee-1.11.0", with: "ee-1.11.1")
        try changed.write(to: stack.appendingPathComponent("docker-compose.yml"), atomically: true, encoding: .utf8)
        let (output, status) = try run(UpdateScript.update(plan()))
        XCTAssertEqual(status, 21, output)
        XCTAssertEqual(try compose(), changed)
    }

    func testRollbackRestoresComposeAndConfig() throws {
        let (output, status) = try run(UpdateScript.update(plan()))
        XCTAssertEqual(status, 0, output)
        let backup = output.components(separatedBy: "\n").first { $0.hasPrefix("PA_BACKUP=") }!
            .replacingOccurrences(of: "PA_BACKUP=", with: "")
        // Simulate a migration that changed the database.
        try "sqlite-v2-migrated".write(to: stack.appendingPathComponent("config/db/db.sqlite"), atomically: true, encoding: .utf8)

        let (rbOutput, rbStatus) = try run(UpdateScript.rollback(deployment, backupPath: backup))
        XCTAssertEqual(rbStatus, 0, rbOutput)
        XCTAssertEqual(try compose(), sampleCompose)
        XCTAssertEqual(try String(contentsOf: stack.appendingPathComponent("config/db/db.sqlite"), encoding: .utf8), "sqlite-v1")
        XCTAssertTrue(rbOutput.contains("PA_STEP=done"))
    }

    func testBackupListing() throws {
        _ = try run(UpdateScript.update(plan()))
        let (output, status) = try run(DeploymentDiscovery.listBackupsScript(deployment))
        XCTAssertEqual(status, 0)
        XCTAssertTrue(output.hasPrefix("pangolin-admin-backups/"), output)
    }
}

extension UpdateScriptExecutionTests {
    func testDetachedRunStreamsLogAndExitCode() throws {
        let script = UpdateScript.update(plan())
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", UpdateScript.detached(script, access: .direct)]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = bin.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        let lines = output.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains { $0.hasPrefix("PA_LOG=/tmp/pangolin-admin-update.") }, output)
        XCTAssertTrue(lines.contains("PA_STEP=done"), output)
        XCTAssertTrue(lines.contains("PA_EXIT=0"), output)
        XCTAssertTrue(try compose().contains("ee-1.12.3"))

        // Re-attaching to the finished job replays the log.
        let log = lines.first { $0.hasPrefix("PA_LOG=") }!.replacingOccurrences(of: "PA_LOG=", with: "")
        let pid = Int(lines.first { $0.hasPrefix("PA_PID=") }!.replacingOccurrences(of: "PA_PID=", with: ""))!
        let replayProcess = Process()
        replayProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        replayProcess.arguments = ["-c", UpdateScript.reattach(log: log, pid: pid, access: .direct)]
        let replayPipe = Pipe()
        replayProcess.standardOutput = replayPipe
        try replayProcess.run()
        let replay = String(decoding: replayPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        replayProcess.waitUntilExit()
        XCTAssertTrue(replay.contains("PA_EXIT=0"), replay)
        try? FileManager.default.removeItem(atPath: log)
    }

    func testDetachedFailureReportsExitCode() throws {
        try installFakeDocker(failPull: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", UpdateScript.detached(UpdateScript.update(plan()), access: .direct)]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = bin.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertTrue(output.contains("PA_EXIT=24"), output)
        XCTAssertEqual(try compose(), sampleCompose)
    }
}
