import SwiftUI
import PangolinKit

struct ResourceDetailView: View {
    let context: OrgContext
    @State var resource: PublicResource

    @Environment(\.dismiss) private var dismiss
    @State private var targets: Loadable<[Target]> = .idle
    @State private var runner = ActionRunner()
    @State private var confirmDelete = false
    @State private var targetToDelete: Target?

    var body: some View {
        GlassScreen {
            GlassCard(tint: resource.healthColor) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StatusPill(text: resource.healthText, color: resource.healthColor)
                        Spacer()
                        Text((resource.mode ?? resource.protocolName ?? "http").uppercased())
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(resource.name).font(.title2.bold())
                    if let domain = resource.fullDomain, let url = URL(string: "https://\(domain)") {
                        Link(destination: url) {
                            Label(resource.displayAddress, systemImage: "safari")
                                .font(.callout)
                        }
                    } else {
                        Text(resource.displayAddress).font(.callout.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }

            GlassSectionHeader(title: "Zugriff", systemImage: "lock.shield")
            GlassCard {
                VStack(spacing: 12) {
                    toggle("Aktiviert", systemImage: "power", value: resource.enabled) { value in
                        UpdateResourceBody(enabled: value)
                    }
                    Divider()
                    toggle("Pangolin-SSO", systemImage: "person.badge.key", value: resource.sso ?? false) { value in
                        UpdateResourceBody(sso: value)
                    }
                    toggle("E-Mail-Whitelist", systemImage: "envelope.badge.shield.half.filled",
                           value: resource.whitelist ?? false) { value in
                        UpdateResourceBody(emailWhitelistEnabled: value)
                    }
                    toggle("Regeln anwenden", systemImage: "list.bullet.rectangle", value: resource.applyRules ?? false) { value in
                        UpdateResourceBody(applyRules: value)
                    }
                    toggle("Zugriff blockieren", systemImage: "hand.raised", value: resource.blockAccess ?? false) { value in
                        UpdateResourceBody(blockAccess: value)
                    }
                    Divider()
                    InfoRow(label: "Passwort", value: resource.passwordId != nil ? "Gesetzt" : "Nein")
                    InfoRow(label: "PIN", value: resource.pincodeId != nil ? "Gesetzt" : "Nein")
                    InfoRow(label: "Header-Auth", value: resource.headerAuthId != nil ? "Gesetzt" : "Nein")
                    InfoRow(label: "mTLS", value: resource.mtls == true ? "Aktiv" : "Nein")
                }
            }

            GlassSectionHeader(title: "Targets", systemImage: "scope")
            switch targets {
            case .idle, .loading:
                ProgressView()
            case .failed(let message):
                GlassMessage(title: "Targets nicht verfügbar", message: message, systemImage: "scope") {
                    Task { await loadTargets() }
                }
            case .loaded(let list):
                if list.isEmpty {
                    GlassMessage(title: "Keine Targets", systemImage: "scope")
                }
                ForEach(list) { target in
                    TargetRow(target: target) { enabled in
                        Task {
                            var body = UpdateTargetBody(target: target)
                            body.enabled = enabled
                            await runner.run(success: "target") { try await context.client.updateTarget(target.targetId, body) }
                            await loadTargets()
                        }
                    }
                    .contextMenu {
                        Button("Target löschen", systemImage: "trash", role: .destructive) { targetToDelete = target }
                    }
                }
            }

            GlassSectionHeader(title: "Details", systemImage: "info.circle")
            GlassCard {
                VStack(spacing: 10) {
                    InfoRow(label: "ID", value: resource.niceId, monospaced: true)
                    InfoRow(label: "SSL", value: resource.ssl.map { $0 ? "Ja" : "Nein" })
                    InfoRow(label: "Port", value: resource.proxyPort.map(String.init))
                    InfoRow(label: "Load Balancing", value: resource.loadBalancingStrategy)
                    InfoRow(label: "Sticky Sessions", value: resource.stickySession.map { $0 ? "Ja" : "Nein" })
                    InfoRow(label: "Sites", value: resource.sites.map(\.siteName).joined(separator: ", "))
                }
            }

            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Ressource löschen", systemImage: "trash").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .tint(.red)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .navigationTitle(resource.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
        .actionErrors(runner)
        .confirmationDialog("Ressource „\(resource.name)“ löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Endgültig löschen", role: .destructive) {
                Task {
                    if await runner.run(success: "delete", { try await context.client.deleteResource(resource.resourceId) }) {
                        dismiss()
                    }
                }
            }
        }
        .confirmationDialog("Target löschen?", isPresented: Binding(get: { targetToDelete != nil },
                                                                   set: { if !$0 { targetToDelete = nil } }),
                            titleVisibility: .visible, presenting: targetToDelete) { target in
            Button("\(target.ip):\(target.port) löschen", role: .destructive) {
                Task {
                    await runner.run(success: "delete-target") { try await context.client.deleteTarget(target.targetId) }
                    await loadTargets()
                }
            }
        }
    }

    private func toggle(_ title: String, systemImage: String, value: Bool,
                        body makeBody: @escaping (Bool) -> UpdateResourceBody) -> some View {
        Toggle(isOn: Binding(
            get: { value },
            set: { newValue in
                Task {
                    let id = resource.resourceId
                    if await runner.run(success: title, { try await context.client.updateResource(id, makeBody(newValue)) }) {
                        await reload()
                    }
                }
            }
        )) {
            Label(title, systemImage: systemImage)
        }
        .disabled(runner.isRunning)
    }

    private func reload() async {
        let fresh = try? await context.client.resource(resource.resourceId)
        await loadTargets()
        if let fresh {
            var merged = fresh
            // Detail responses do not embed targets/sites/health.
            if merged.targets.isEmpty { merged.targets = resource.targets }
            if merged.sites.isEmpty { merged.sites = resource.sites }
            if merged.labels.isEmpty { merged.labels = resource.labels }
            merged.health = merged.health ?? resource.health
            merged.whitelist = merged.whitelist ?? resource.whitelist
            merged.mtls = merged.mtls ?? resource.mtls
            resource = merged
        }
    }

    private func loadTargets() async {
        if targets.value == nil { targets = .loading }
        do {
            targets = .loaded(try await context.client.targets(resourceId: resource.resourceId).items)
        } catch is CancellationError {
        } catch {
            targets = .failed(error.localizedDescription)
        }
    }
}

private struct TargetRow: View {
    let target: Target
    let onToggle: (Bool) -> Void

    private var healthColor: Color {
        switch target.hcHealth {
        case "healthy": .green
        case "unhealthy": .red
        default: .gray
        }
    }

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Circle().fill(healthColor).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.displayAddress).font(.callout.monospaced()).lineLimit(1)
                    Text([target.siteName, target.hcEnabled == true ? "Health-Check aktiv" : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Aktiv", isOn: Binding(get: { target.enabled }, set: onToggle))
                    .labelsHidden()
            }
        }
    }
}
