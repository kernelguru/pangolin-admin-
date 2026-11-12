import PangolinSSH
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Configures SSH access for server updates: host, key (Secure Enclave or import),
/// CA certificate and the pinned host key.
struct SSHSetupView: View {
    let profile: ServerProfile

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var port: Int? = 22
    @State private var username = ""
    @State private var identity: SSHIdentity?
    @State private var certificateText = ""
    @State private var hostKeyFingerprint: String?
    @State private var pendingFingerprint: String?
    @State private var importText = ""
    @State private var showsImport = false
    @State private var importingFile: FileTarget?
    @State private var runner = ActionRunner()
    @State private var testMessage: String?
    @State private var didLoad = false

    enum FileTarget: String, Identifiable {
        case key, certificate
        var id: String { rawValue }
    }

    private var certificateInfo: Result<SSHCertificateInfo, Error>? {
        let trimmed = certificateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Result { try SSHCertificateInfo(trimmed) }
    }

    private var certificateProblem: String? {
        guard let identity, let info = certificateInfo else { return nil }
        switch info {
        case .failure(let error):
            return error.localizedDescription
        case .success(let info):
            if (try? identity.withCertificate(certificateText)) == nil { return SSHKeyError.certificateDoesNotMatchKey.errorDescription }
            if info.type != .user { return SSHKeyError.notAUserCertificate.errorDescription }
            if !info.isValid() { return "Das Zertifikat ist abgelaufen oder noch nicht gültig." }
            if !username.isEmpty, !info.principals.isEmpty, !info.principals.contains(username) {
                return "Das Zertifikat gilt nicht für den Benutzer „\(username)“ (Principals: \(info.principals.joined(separator: ", ")))."
            }
            return nil
        }
    }

    private var canSave: Bool {
        !host.isEmpty && !username.isEmpty && identity != nil && hostKeyFingerprint != nil && certificateProblem == nil
    }

    private var publicKeyLine: String? {
        try? identity?.publicKeyLine(comment: "pangolin-admin-\(UIDevice.current.name.replacingOccurrences(of: " ", with: "-"))")
    }

    private var signCommand: String {
        "ssh-keygen -s /pfad/zur/ca -I pangolin-admin-iphone -n \(username.isEmpty ? "<benutzer>" : username) -V +52w pangolin-admin.pub"
    }

    var body: some View {
        Form {
            Section {
                TextField("Host oder IP", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                IntField(title: "Port", value: $port, prompt: "22")
                TextField("Benutzer", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Docker-Host")
            } footer: {
                Text("Der Server, auf dem Pangolin per Docker Compose läuft. Der Benutzer braucht Docker-Rechte (Gruppe „docker“) oder sudo ohne Passwort.")
            }

            keySection
            if identity != nil { certificateSection }
            hostKeySection

            if let testMessage {
                Section { Text(testMessage).font(.footnote) }
            }
        }
        .navigationTitle("SSH-Zugang")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { save() }.disabled(!canSave)
            }
        }
        .sheet(isPresented: $showsImport) { importSheet }
        .fileImporter(isPresented: Binding(get: { importingFile != nil }, set: { if !$0 { importingFile = nil } }),
                      allowedContentTypes: [.data, .text, .plainText]) { result in
            handleFile(result)
        }
        .confirmationDialog("Host-Schlüssel vertrauen?", isPresented: Binding(get: { pendingFingerprint != nil },
                                                                             set: { if !$0 { pendingFingerprint = nil } }),
                            titleVisibility: .visible, presenting: pendingFingerprint) { fingerprint in
            Button("Vertrauen und merken") { hostKeyFingerprint = fingerprint }
            Button("Abbrechen", role: .cancel) {}
        } message: { fingerprint in
            Text("Vergleiche mit der Ausgabe von\n„ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub“ auf dem Server:\n\n\(fingerprint)")
        }
        .actionErrors(runner)
        .onAppear(perform: load)
    }

    // MARK: Sections

    @ViewBuilder
    private var keySection: some View {
        Section {
            if let identity {
                LabeledContent("Typ", value: identity.algorithm.displayName)
                if let fingerprint = try? identity.publicKeyFingerprint() {
                    LabeledContent("Fingerprint") {
                        Text(fingerprint).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                if let line = publicKeyLine {
                    Text(line)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(4)
                    HStack {
                        Button("Kopieren", systemImage: "doc.on.doc") { UIPasteboard.general.string = line }
                        Spacer()
                        ShareLink(item: line, subject: Text("pangolin-admin.pub")) {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                        }
                    }
                    .buttonStyle(.borderless)
                }
                Button("Schlüssel ersetzen", role: .destructive) {
                    self.identity = nil
                    certificateText = ""
                }
            } else {
                Button {
                    generate()
                } label: {
                    Label("Neuen Schlüssel in der Secure Enclave erzeugen", systemImage: "cpu")
                }
                Button {
                    showsImport = true
                } label: {
                    Label("Vorhandenen Schlüssel importieren", systemImage: "square.and.arrow.down")
                }
            }
        } header: {
            Text("Schlüssel")
        } footer: {
            Text(identity?.algorithm == .secureEnclaveP256
                 ? "Der private Schlüssel liegt in der Secure Enclave und kann das Gerät nicht verlassen."
                 : "Importierte Schlüssel werden in der iOS-Keychain (nur dieses Gerät) gespeichert. Unterstützt: ed25519, ECDSA.")
        }
    }

    @ViewBuilder
    private var certificateSection: some View {
        Section {
            TextField("ssh-…-cert-v01@openssh.com AAAA…", text: $certificateText, axis: .vertical)
                .font(.caption.monospaced())
                .lineLimit(3...6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Button("Einfügen", systemImage: "doc.on.clipboard") {
                    certificateText = UIPasteboard.general.string ?? certificateText
                }
                Spacer()
                Button("Datei wählen", systemImage: "folder") { importingFile = .certificate }
            }
            .buttonStyle(.borderless)

            if case .success(let info) = certificateInfo {
                LabeledContent("Key-ID", value: info.keyID)
                LabeledContent("Principals", value: info.principals.isEmpty ? "alle" : info.principals.joined(separator: ", "))
                LabeledContent("Gültig bis", value: info.validBefore.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "unbegrenzt")
                LabeledContent("CA") { Text(info.caFingerprint).font(.caption2.monospaced()) }
            }
            if let problem = certificateProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Zertifikat der SSH-CA")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Öffentlichen Schlüssel als pangolin-admin.pub speichern und mit deiner CA signieren:")
                Text(signCommand).font(.caption2.monospaced()).textSelection(.enabled)
                Text("Den Inhalt von pangolin-admin-cert.pub hier einfügen. Ohne Zertifikat funktioniert auch ein Eintrag des öffentlichen Schlüssels in ~/.ssh/authorized_keys.")
            }
        }
    }

    @ViewBuilder
    private var hostKeySection: some View {
        Section {
            if let hostKeyFingerprint {
                LabeledContent("Vertraut") {
                    Text(hostKeyFingerprint).font(.caption2.monospaced()).textSelection(.enabled)
                }
                Button("Host-Schlüssel zurücksetzen", role: .destructive) { self.hostKeyFingerprint = nil }
            }
            Button {
                Task { await testConnection() }
            } label: {
                Label(hostKeyFingerprint == nil ? "Verbinden und Host-Schlüssel prüfen" : "Verbindung testen",
                      systemImage: "network.badge.shield.half.filled")
            }
            .disabled(host.isEmpty || username.isEmpty || identity == nil || runner.isRunning)
        } header: {
            Text("Host-Schlüssel")
        } footer: {
            Text("Beim ersten Verbinden zeigt die App den Fingerprint des Servers. Danach werden nur noch Verbindungen mit genau diesem Schlüssel akzeptiert.")
        }
    }

    private var importSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("-----BEGIN OPENSSH PRIVATE KEY-----", text: $importText, axis: .vertical)
                        .font(.caption2.monospaced())
                        .lineLimit(6...14)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Aus Zwischenablage einfügen", systemImage: "doc.on.clipboard") {
                        importText = UIPasteboard.general.string ?? importText
                    }
                    Button("Datei wählen", systemImage: "folder") {
                        showsImport = false
                        importingFile = .key
                    }
                } footer: {
                    Text("Unverschlüsselter OpenSSH-Schlüssel (ed25519 oder ECDSA). Verschlüsselte Schlüssel vorher mit „ssh-keygen -p -N \"\" -f kopie“ entschlüsseln.")
                }
            }
            .navigationTitle("Schlüssel importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { showsImport = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importieren") { importKey(importText) }
                        .disabled(importText.isEmpty)
                }
            }
        }
    }

    // MARK: Actions

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let ssh = profile.ssh {
            host = ssh.host
            port = ssh.port
            username = ssh.username
            hostKeyFingerprint = ssh.hostKeyFingerprint
            certificateText = ssh.certificate ?? ""
        } else {
            // Suggest the Pangolin host: api.pangolin.example.com → pangolin.example.com
            var suggestion = profile.host
            if suggestion.hasPrefix("api.") { suggestion = String(suggestion.dropFirst(4)) }
            host = suggestion
        }
        if let key = model.sshKey(for: profile) {
            identity = try? SSHIdentity(serialized: key, certificate: nil)
        }
    }

    private func generate() {
        do {
            identity = try SSHIdentity.generate(useSecureEnclave: true)
        } catch SSHKeyError.secureEnclaveUnavailable {
            // Simulator or device without Secure Enclave: fall back to an ed25519 key in the Keychain.
            identity = try? SSHIdentity.generate(useSecureEnclave: false)
        } catch {
            runner.errorMessage = error.localizedDescription
        }
    }

    private func importKey(_ text: String) {
        do {
            identity = try SSHIdentity.importOpenSSH(text)
            importText = ""
            showsImport = false
        } catch {
            runner.errorMessage = error.localizedDescription
        }
    }

    private func handleFile(_ result: Result<URL, Error>) {
        guard let target = importingFile else { return }
        importingFile = nil
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let text = try String(contentsOf: url, encoding: .utf8)
            switch target {
            case .key: importKey(text)
            case .certificate: certificateText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            runner.errorMessage = error.localizedDescription
        }
    }

    private func currentIdentity() throws -> SSHIdentity {
        guard let identity else { throw SSHKeyError.invalidKey("Kein Schlüssel") }
        let cert = certificateText.trimmingCharacters(in: .whitespacesAndNewlines)
        return try identity.withCertificate(cert.isEmpty ? nil : cert)
    }

    private func testConnection() async {
        testMessage = nil
        await runner.run {
            let server = SSHServer(host: host.trimmingCharacters(in: .whitespaces), port: port ?? 22,
                                   username: username.trimmingCharacters(in: .whitespaces))
            let policy: SSHHostKeyPolicy = hostKeyFingerprint.map { .pinned($0) } ?? .trustOnFirstUse
            let connection = try await SSHConnection.connect(to: server, identity: try currentIdentity(), hostKey: policy)
            let result = try await connection.collect("id -un; (docker --version || true) 2>&1 | head -1")
            await connection.close()
            testMessage = "Verbunden als \(result.stdout.replacingOccurrences(of: "\n", with: " · "))"
            if hostKeyFingerprint == nil { pendingFingerprint = connection.hostKeyFingerprint }
        }
    }

    private func save() {
        do {
            let identity = try currentIdentity()
            try model.saveSSHKey(identity.serialized, for: profile)
            var settings = profile.ssh ?? SSHSettings(host: "", username: "")
            settings.host = host.trimmingCharacters(in: .whitespaces)
            settings.port = port ?? 22
            settings.username = username.trimmingCharacters(in: .whitespaces)
            settings.hostKeyFingerprint = hostKeyFingerprint
            settings.certificate = identity.certificate
            model.updateSSH(settings, for: profile.id)
            dismiss()
        } catch {
            runner.errorMessage = error.localizedDescription
        }
    }
}
