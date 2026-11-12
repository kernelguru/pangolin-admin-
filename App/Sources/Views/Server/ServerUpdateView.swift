import PangolinUpdater
import SwiftUI

/// Updates the Pangolin Docker stack over SSH: inspect, choose images, run with live log, roll back.
struct ServerUpdateView: View {
    let context: OrgContext

    @Environment(AppModel.self) private var appModel
    @State private var model: ServerUpdateModel?
    @State private var showsSetup = false
    @State private var confirmUpdate = false
    @State private var rollbackTarget: String?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Server-Update")
        .onAppear {
            if model == nil { model = ServerUpdateModel(appModel: appModel, context: context) }
        }
        .sheet(isPresented: $showsSetup) {
            if let profile = appModel.activeProfile {
                NavigationStack { SSHSetupView(profile: profile) }
            }
        }
    }

    @ViewBuilder
    private func content(_ model: ServerUpdateModel) -> some View {
        GlassScreen {
            connectionCard(model)

            if !model.isConfigured {
                GlassMessage(title: "SSH noch nicht eingerichtet",
                             message: "Für Updates verbindet sich die App per SSH mit dem Docker-Host, findet die docker-compose.yml von Pangolin und aktualisiert die Images – mit Sicherung und Wiederherstellung.",
                             systemImage: "terminal")
                Button {
                    showsSetup = true
                } label: {
                    Label("SSH einrichten", systemImage: "key.horizontal").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            } else {
                phaseCard(model)

                if let deployment = model.deployment {
                    deploymentCard(deployment, access: model.accessMode)
                }

                if !model.updates.isEmpty {
                    GlassSectionHeader(title: "Images", systemImage: "shippingbox")
                    ForEach(model.updates) { update in
                        ImageUpdateRow(update: update, isSelected: Binding(
                            get: { model.selected.contains(update.id) },
                            set: { on in
                                if on { model.selected.insert(update.id) } else { model.selected.remove(update.id) }
                            }))
                    }
                    Text("Images ohne Versionsnummer im Tag (z. B. redis:8-trixie) werden beim Update nur neu geladen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)

                    Button {
                        confirmUpdate = true
                    } label: {
                        Label(model.plannedRetags.isEmpty ? "Images neu laden & neu starten" : "Update ausführen",
                              systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(model.isBusy)
                }

                if !model.console.isEmpty {
                    GlassSectionHeader(title: "Ausgabe", systemImage: "terminal")
                    ConsoleView(lines: model.console)
                }

                if !model.backups.isEmpty {
                    GlassSectionHeader(title: "Sicherungen auf dem Server", systemImage: "clock.arrow.circlepath")
                    ForEach(model.backups.prefix(5), id: \.self) { backup in
                        GlassCard(padding: 12) {
                            HStack {
                                Label(backupTitle(backup), systemImage: "archivebox")
                                    .font(.callout)
                                Spacer()
                                Button("Zurückrollen") { rollbackTarget = backup }
                                    .buttonStyle(.glass)
                                    .disabled(model.isBusy)
                            }
                        }
                    }
                }
            }
        }
        .refreshable { if model.isConfigured { await model.inspect() } }
        .task(id: model.isConfigured) {
            if model.isConfigured, model.phase == .idle { await model.inspect() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("SSH-Einstellungen", systemImage: "gearshape") { showsSetup = true }
            }
        }
        .confirmationDialog("Update ausführen?", isPresented: $confirmUpdate, titleVisibility: .visible) {
            Button("Jetzt aktualisieren") { Task { await model.runUpdate() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(updateSummary(model))
        }
        .confirmationDialog("Auf diese Sicherung zurückrollen?", isPresented: Binding(
            get: { rollbackTarget != nil }, set: { if !$0 { rollbackTarget = nil } }),
                            titleVisibility: .visible, presenting: rollbackTarget) { backup in
            Button("Zurückrollen", role: .destructive) { Task { await model.rollback(to: backup) } }
        } message: { backup in
            Text("Stoppt den Stack, stellt docker-compose.yml und den config-Ordner (inkl. SQLite-Datenbank) vom \(backupTitle(backup)) wieder her und startet neu. Änderungen seit dieser Sicherung gehen verloren.")
        }
    }

    // MARK: Cards

    private func connectionCard(_ model: ServerUpdateModel) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    if let ssh = model.settings, !ssh.host.isEmpty {
                        Text("\(ssh.username)@\(ssh.host)").font(.headline)
                        Text(ssh.certificate != nil ? "Anmeldung mit CA-Zertifikat" : "Anmeldung mit Schlüssel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Kein Docker-Host").font(.headline)
                    }
                }
                Spacer()
                if model.isConfigured {
                    Button {
                        Task { await model.inspect() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                    .disabled(model.isBusy)
                }
            }
        }
    }

    @ViewBuilder
    private func phaseCard(_ model: ServerUpdateModel) -> some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .inspecting:
            GlassCard {
                HStack { ProgressView(); Text("Verbinde und prüfe Versionen …") }
            }
        case .ready:
            let count = model.updates.filter { $0.newReference != nil }.count
            GlassCard(tint: count > 0 ? Color.blue : Color.green) {
                Label(count > 0 ? "\(count) Update(s) verfügbar" : "Alles aktuell",
                      systemImage: count > 0 ? "arrow.up.circle.fill" : "checkmark.seal.fill")
                    .font(.headline)
            }
        case .running(let step):
            GlassCard(tint: .blue) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { ProgressView(); Text(step).font(.headline) }
                    Text("Das Update läuft auf dem Server weiter, auch wenn die App in den Hintergrund geht.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .verifying:
            GlassCard(tint: .blue) {
                HStack { ProgressView(); Text("Warte, bis Pangolin wieder antwortet …") }
            }
        case .finished(let success, let message):
            GlassCard(tint: success ? Color.green : Color.red) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: success ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(success ? .green : .red)
                    if let backup = model.lastBackup {
                        Text("Sicherung: \(backup)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        if !success {
                            Button("Auf diese Sicherung zurückrollen") { rollbackTarget = backup }
                                .buttonStyle(.glass)
                        }
                    }
                }
            }
        case .failed(let message):
            GlassCard(tint: .red) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    HStack {
                        Button("Erneut prüfen") { Task { await model.inspect() } }
                            .buttonStyle(.glass)
                        if model.settings?.lastJobLog != nil {
                            Button("Erneut verbinden") { Task { await model.reattach() } }
                                .buttonStyle(.glass)
                        }
                    }
                }
            }
        }
    }

    private func deploymentCard(_ deployment: PangolinDeployment, access: DockerAccess?) -> some View {
        GlassCard {
            VStack(spacing: 8) {
                InfoRow(label: "Compose-Datei", value: deployment.composeFile, monospaced: true)
                InfoRow(label: "Projekt", value: deployment.project)
                InfoRow(label: "Läuft", value: deployment.container.image, monospaced: true)
                InfoRow(label: "Docker", value: access == .sudo ? "über sudo" : "direkt")
                InfoRow(label: "Container", value: deployment.projectContainers
                    .map { "\($0.name) (\($0.state))" }.joined(separator: ", "))
            }
        }
    }

    // MARK: Helpers

    private func updateSummary(_ model: ServerUpdateModel) -> String {
        var lines = model.plannedRetags.map { update in
            "\(update.image.service ?? update.image.image.repository): \(update.image.image.tag ?? "") → \(update.newReference.flatMap { ImageReference($0)?.tag } ?? "")"
        }
        if lines.isEmpty { lines = ["Keine Versionsänderung – Images werden nur neu geladen."] }
        lines.append("")
        lines.append("Ablauf: Sicherung → Images laden (Stack läuft weiter) → kurz stoppen → config sichern → starten. Pangolin ist dabei etwa 10–60 Sekunden nicht erreichbar.")
        return lines.joined(separator: "\n")
    }

    private func backupTitle(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        let parser = DateFormatter()
        parser.dateFormat = "yyyyMMdd-HHmmss"
        if let date = parser.date(from: name) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return name
    }
}

private struct ImageUpdateRow: View {
    let update: ImageUpdate
    @Binding var isSelected: Bool

    private var status: (String, Color) {
        switch update.action {
        case .retag:
            if update.tagVerified == false { return ("Tag fehlt auf Docker Hub", .red) }
            return (update.isMajorUpgrade ? "Major-Update" : "Update", update.isMajorUpgrade ? .orange : .blue)
        case .upToDate: return ("Aktuell", .green)
        case .pullOnly: return ("Nur neu laden", .gray)
        case .unknown: return ("Version unbekannt", .gray)
        }
    }

    var body: some View {
        GlassCard(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(update.image.service ?? update.image.image.repository).font(.headline)
                        StatusPill(text: status.0, color: status.1)
                    }
                    Text(update.image.image.raw).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    if let new = update.newReference {
                        Label(new, systemImage: "arrow.turn.down.right")
                            .font(.caption.monospaced())
                            .lineLimit(1)
                    }
                    if update.isMajorUpgrade {
                        Text("Neue Hauptversion – vorher die Release-Notes lesen, Konfigurationen können sich ändern.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                if update.newReference != nil {
                    Toggle("Aktualisieren", isOn: $isSelected)
                        .labelsHidden()
                        .disabled(update.tagVerified == false)
                }
            }
        }
    }
}

private struct ConsoleView: View {
    let lines: [ConsoleLine]

    var body: some View {
        GlassCard(padding: 12) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines) { line in
                            Text(line.text)
                                .font(line.kind == .step ? .caption.monospaced().bold() : .caption2.monospaced())
                                .foregroundStyle(color(line.kind))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                }
                .frame(height: 260)
                .onChange(of: lines.count) {
                    if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func color(_ kind: ConsoleLine.Kind) -> Color {
        switch kind {
        case .output: .primary
        case .error: .red
        case .step: .blue
        case .warning: .orange
        case .success: .green
        }
    }
}
