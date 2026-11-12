import Foundation
import Observation
import PangolinKit
import PangolinSSH
import PangolinUpdater
import UIKit

/// One line in the live update console.
struct ConsoleLine: Identifiable, Hashable {
    enum Kind { case output, error, step, warning, success }
    let id = UUID()
    let text: String
    let kind: Kind
}

/// Drives the server update: SSH connect, inspection, update run and rollback.
@MainActor
@Observable
final class ServerUpdateModel {
    enum Phase: Equatable {
        case idle
        case inspecting
        case ready
        case running(step: String)
        case verifying
        case finished(success: Bool, message: String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var deployment: PangolinDeployment?
    private(set) var updates: [ImageUpdate] = []
    var selected: Set<Int> = []
    private(set) var console: [ConsoleLine] = []
    private(set) var backups: [String] = []
    private(set) var lastBackup: String?
    private(set) var accessMode: DockerAccess?

    let profileID: UUID
    private let appModel: AppModel
    private let context: OrgContext

    init(appModel: AppModel, context: OrgContext) {
        self.appModel = appModel
        self.context = context
        self.profileID = context.profileID
    }

    var profile: ServerProfile? { appModel.profiles.first { $0.id == profileID } }
    var settings: SSHSettings? { profile?.ssh }

    var isConfigured: Bool {
        guard let settings, let profile else { return false }
        return !settings.host.isEmpty && !settings.username.isEmpty
            && settings.hostKeyFingerprint != nil && appModel.sshKey(for: profile) != nil
    }

    var isBusy: Bool {
        switch phase {
        case .inspecting, .running, .verifying: true
        default: false
        }
    }

    var plannedRetags: [ImageUpdate] { updates.filter { selected.contains($0.id) && $0.newReference != nil } }

    // MARK: Connection

    private func identity() throws -> SSHIdentity {
        guard let profile, let key = appModel.sshKey(for: profile) else {
            throw SSHKeyError.invalidKey("Kein SSH-Schlüssel gespeichert.")
        }
        return try SSHIdentity(serialized: key, certificate: settings?.certificate)
    }

    private func connect() async throws -> SSHConnection {
        guard let settings, let fingerprint = settings.hostKeyFingerprint else {
            throw SSHError.connectionFailed("SSH ist nicht eingerichtet.")
        }
        return try await SSHConnection.connect(
            to: SSHServer(host: settings.host, port: settings.port, username: settings.username),
            identity: try identity(),
            hostKey: .pinned(fingerprint))
    }

    // MARK: Inspect

    /// Finds the deployment, reads the compose file and looks up newer versions.
    func inspect() async {
        phase = .inspecting
        console = []
        do {
            let connection = try await connect()
            defer { Task { await connection.close() } }

            let probe = try await connection.collect(DeploymentDiscovery.accessProbeCommand)
            let access = try DeploymentDiscovery.parseAccess(probe.combinedOutput)
            accessMode = access

            let list = try await connection.collect(access.wrap(DeploymentDiscovery.listContainersScript))
            guard list.succeeded else { throw SSHError.commandFailed(exitCode: list.exitCode ?? -1, output: list.combinedOutput) }
            let deployment = try DeploymentDiscovery.findDeployment(
                containers: DeploymentDiscovery.parseContainers(list.stdout), access: access)
            self.deployment = deployment

            let compose = try await connection.collect(access.wrap(DeploymentDiscovery.readComposeScript(deployment)))
            guard compose.succeeded else {
                throw SSHError.commandFailed(exitCode: compose.exitCode ?? -1, output: compose.combinedOutput)
            }
            let images = ComposeFile.images(in: compose.stdout)

            let backupList = try? await connection.collect(access.wrap(DeploymentDiscovery.listBackupsScript(deployment)))
            backups = (backupList?.stdout ?? "").split(separator: "\n").map { String($0).trimmingSuffix("/") }

            updates = await ReleaseLookup().evaluate(images)
            // Preselect regular updates; never preselect major jumps or unverified tags.
            selected = Set(updates.filter { $0.newReference != nil && !$0.isMajorUpgrade && $0.tagVerified != false }.map(\.id))
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Update / rollback

    func runUpdate() async {
        guard let deployment else { return }
        let plan = UpdatePlan(deployment: deployment, updates: updates, selected: selected,
                              postgresService: UpdatePlan.postgresService(in: updates.map(\.image)))
        await runDetached(UpdateScript.update(plan), title: "Update")
    }

    func rollback(to backup: String) async {
        guard let deployment else { return }
        let path = backup.hasPrefix("/") ? backup : (deployment.workingDir as NSString).appendingPathComponent(backup)
        await runDetached(UpdateScript.rollback(deployment, backupPath: path), title: "Wiederherstellung")
    }

    /// Re-attaches to the last job (e.g. after the app was in the background).
    func reattach() async {
        if deployment == nil { await inspect() }
        guard let settings, let log = settings.lastJobLog, let pid = settings.lastJobPID,
              let access = accessMode ?? deployment?.access else { return }
        await stream(UpdateScript.reattach(log: log, pid: pid, access: access), title: "Update")
    }

    private func runDetached(_ script: String, title: String) async {
        guard let access = deployment?.access else { return }
        console = []
        await stream(UpdateScript.detached(script, access: access), title: title)
    }

    private func stream(_ command: String, title: String) async {
        phase = .running(step: "Verbinden")
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        var exitCode: Int?
        var errorMessage: String?
        do {
            let connection = try await connect()
            defer { Task { await connection.close() } }
            for try await event in connection.run(command) {
                switch event {
                case .stdout(let line), .stderr(let line):
                    if let code = handleMarker(line) { exitCode = code }
                    if line.hasPrefix("PA_ERROR=") { errorMessage = String(line.dropFirst(9)) }
                case .exit:
                    break
                }
            }
        } catch {
            append(error.localizedDescription, .error)
            phase = .failed("Verbindung unterbrochen – das Update läuft auf dem Server weiter. Mit „Erneut verbinden“ siehst du den Fortschritt.\n\(error.localizedDescription)")
            return
        }

        guard exitCode == 0 else {
            phase = .finished(success: false, message: errorMessage ?? "\(title) fehlgeschlagen (Exit-Code \(exitCode.map(String.init) ?? "?")).")
            return
        }
        phase = .verifying
        let healthy = await waitForPangolin()
        phase = .finished(success: healthy, message: healthy
            ? "\(title) abgeschlossen – Pangolin antwortet wieder."
            : "\(title) ausgeführt, aber die Integration API antwortet noch nicht. Prüfe die Container-Logs (docker compose logs pangolin).")
        await inspect()
    }

    /// Parses `PA_*` markers; returns the exit code for `PA_EXIT`.
    private func handleMarker(_ line: String) -> Int? {
        if line.hasPrefix("PA_STEP=") {
            let step = Self.stepTitle(String(line.dropFirst(8)))
            phase = .running(step: step)
            append(step, .step)
        } else if line.hasPrefix("PA_BACKUP=") {
            lastBackup = String(line.dropFirst(10))
            append("Sicherung: \(lastBackup ?? "")", .success)
        } else if line.hasPrefix("PA_ERROR=") {
            append(String(line.dropFirst(9)), .error)
        } else if line.hasPrefix("PA_WARN=") {
            append(String(line.dropFirst(8)), .warning)
        } else if line.hasPrefix("PA_LOG=") {
            var settings = self.settings
            settings?.lastJobLog = String(line.dropFirst(7))
            appModel.updateSSH(settings, for: profileID)
        } else if line.hasPrefix("PA_PID=") {
            var settings = self.settings
            settings?.lastJobPID = Int(line.dropFirst(7))
            appModel.updateSSH(settings, for: profileID)
        } else if line.hasPrefix("PA_EXIT=") {
            return Int(line.dropFirst(8))
        } else {
            append(line, .output)
        }
        return nil
    }

    private func append(_ text: String, _ kind: ConsoleLine.Kind) {
        console.append(ConsoleLine(text: text, kind: kind))
        if console.count > 2000 { console.removeFirst(console.count - 2000) }
    }

    /// Polls the Integration API until Pangolin is back (max. ~3 minutes).
    private func waitForPangolin() async -> Bool {
        for _ in 0..<36 {
            if (try? await context.client.organization(context.orgId)) != nil { return true }
            try? await Task.sleep(for: .seconds(5))
        }
        return false
    }

    static func stepTitle(_ step: String) -> String {
        switch step {
        case "backup": "Sicherung anlegen"
        case "edit": "docker-compose.yml anpassen"
        case "pull": "Images herunterladen"
        case "stop": "Container stoppen"
        case "snapshot": "Konfiguration sichern"
        case "restore": "Sicherung zurückspielen"
        case "up": "Container starten"
        case "status": "Status prüfen"
        case "done": "Fertig"
        default: step
        }
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
