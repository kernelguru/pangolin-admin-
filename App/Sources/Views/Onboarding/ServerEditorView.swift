import SwiftUI
import PangolinKit

/// Adds or edits a server profile. The API key goes straight to the Keychain.
struct ServerEditorView: View {
    enum Mode: Equatable {
        case onboarding
        case add
        case edit(ServerProfile)
    }

    let mode: Mode

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var baseURL = "https://"
    @State private var apiKey = ""
    @State private var orgId = ""
    @State private var isRootKey = false
    @State private var testState: TestState = .idle
    @State private var saveError: String?

    enum TestState: Equatable {
        case idle, testing, success(String), failure(String)
    }

    private var existing: ServerProfile? {
        if case .edit(let profile) = mode { return profile }
        return nil
    }

    private var draft: ServerProfile {
        ServerProfile(id: existing?.id ?? UUID(),
                      name: name.trimmingCharacters(in: .whitespaces).isEmpty ? hostName : name,
                      baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                      orgId: orgId.trimmingCharacters(in: .whitespaces).isEmpty ? nil : orgId.trimmingCharacters(in: .whitespaces),
                      isRootKey: isRootKey)
    }

    private var hostName: String { URL(string: baseURL)?.host ?? "Pangolin" }

    private var canSave: Bool {
        draft.url != nil
            && (existing != nil || !apiKey.isEmpty)
            && (isRootKey || draft.orgId != nil)
    }

    var body: some View {
        GlassScreen {
            if mode == .onboarding { header }

            GlassSectionHeader(title: "Server", systemImage: "server.rack")
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    field("Name", text: $name, prompt: "z. B. Homelab")
                    field("Integration-API-URL", text: $baseURL, prompt: "https://api.example.com/v1")
                        .keyboardType(.URL)
                    Text("Die URL, unter der der Integration-API-Port (Standard 3003) per Reverse Proxy erreichbar ist. „/v1“ wird bei Bedarf ergänzt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GlassSectionHeader(title: "Zugang", systemImage: "key.horizontal")
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API-Schlüssel").font(.caption).foregroundStyle(.secondary)
                        SecureField(existing == nil ? "Schlüssel einfügen" : "Unverändert lassen", text: $apiKey)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                    }
                    Toggle("Root-Schlüssel (Server-Admin)", isOn: $isRootKey)
                    field(isRootKey ? "Standard-Organisation (optional)" : "Organisations-ID",
                          text: $orgId, prompt: "z. B. homelab")
                    Label("Der Schlüssel wird ausschließlich in der iOS-Keychain dieses Geräts gespeichert (nicht in iCloud).",
                          systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            testResult

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        Task { await test() }
                    } label: {
                        Label("Testen", systemImage: "antenna.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(draft.url == nil || (apiKey.isEmpty && existing == nil) || testState == .testing)

                    Button {
                        Task { await save() }
                    } label: {
                        Label("Speichern", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canSave)
                }
                .controlSize(.large)
            }
            .padding(.top, 8)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(mode == .onboarding ? .large : .inline)
        .toolbar {
            if mode != .onboarding {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
            }
        }
        .alert("Speichern fehlgeschlagen", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .onAppear(perform: populate)
    }

    private var title: String {
        switch mode {
        case .onboarding: "Willkommen"
        case .add: "Server hinzufügen"
        case .edit: "Server bearbeiten"
        }
    }

    private var header: some View {
        GlassCard(tint: .accentColor) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("Pangolin Admin").font(.title2.bold())
                Text("Verwalte Sites, Ressourcen, Clients und Benutzer deines selbst gehosteten Pangolin-Servers über die Integration API.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var testResult: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            GlassCard {
                HStack { ProgressView(); Text("Verbindung wird geprüft …") }
            }
        case .success(let message):
            GlassCard(tint: .green) {
                Label(message, systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            }
        case .failure(let message):
            GlassCard(tint: .red) {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private func populate() {
        guard let existing, name.isEmpty else { return }
        name = existing.name
        baseURL = existing.baseURL
        orgId = existing.orgId ?? ""
        isRootKey = existing.isRootKey
    }

    private func resolvedKey() -> String? {
        if !apiKey.isEmpty { return apiKey }
        guard let existing else { return nil }
        return model.storedAPIKey(for: existing)
    }

    private func test() async {
        guard let url = draft.url, let key = resolvedKey() else { return }
        testState = .testing
        do {
            let orgs = try await model.test(baseURL: url, apiKey: key, orgId: isRootKey ? nil : draft.orgId)
            let names = orgs.prefix(3).map(\.name).joined(separator: ", ")
            testState = .success(orgs.count == 1 ? "Verbunden mit „\(names)“" : "Verbunden – \(orgs.count) Organisationen (\(names))")
            if isRootKey, draft.orgId == nil, let first = orgs.first { orgId = first.orgId }
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }

    private func save() async {
        let profile = draft
        do {
            try model.save(profile, apiKey: apiKey.isEmpty ? nil : apiKey)
            apiKey = ""
            await model.connect(to: profile)
            if mode != .onboarding { dismiss() }
        } catch {
            saveError = error.localizedDescription
        }
    }
}
