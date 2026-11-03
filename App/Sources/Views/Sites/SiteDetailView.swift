import SwiftUI
import PangolinKit

struct SiteDetailView: View {
    let context: OrgContext
    @State var site: Site

    @Environment(\.dismiss) private var dismiss
    @State private var runner = ActionRunner()
    @State private var confirmDelete = false
    @State private var confirmReject = false
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        GlassScreen {
            GlassCard(tint: site.statusColor) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StatusPill(text: site.statusText, color: site.statusColor)
                        Spacer()
                        Text(site.typeText).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(site.name).font(.title2.bold())
                    Text(site.niceId).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
            }

            if !site.isLocal {
                HStack(spacing: 12) {
                    MetricTile(title: "Eingehend", value: Format.traffic(site.megabytesIn), systemImage: "arrow.down", tint: .blue)
                    MetricTile(title: "Ausgehend", value: Format.traffic(site.megabytesOut), systemImage: "arrow.up", tint: .purple)
                }
            }

            GlassSectionHeader(title: "Details", systemImage: "info.circle")
            GlassCard {
                VStack(spacing: 10) {
                    InfoRow(label: "Adresse", value: site.address, monospaced: true)
                    InfoRow(label: "Subnetz", value: site.subnet, monospaced: true)
                    InfoRow(label: "Endpunkt", value: site.endpoint, monospaced: true)
                    InfoRow(label: "Exit-Node", value: site.exitNodeName)
                    InfoRow(label: "Ressourcen", value: site.resourceCount.map(String.init))
                    if site.type == "newt" {
                        InfoRow(label: "Newt-Version", value: [site.newtVersion ?? site.agentVersion,
                                                              site.newtUpdateAvailable == true ? "(Update verfügbar)" : nil]
                            .compactMap { $0 }.joined(separator: " "))
                    }
                    InfoRow(label: "Docker-Socket", value: site.dockerSocketEnabled.map { $0 ? "Aktiv" : "Aus" })
                    InfoRow(label: "Auto-Update", value: site.autoUpdateEnabled.map { $0 ? "Aktiv" : "Aus" })
                    InfoRow(label: "Land", value: site.countryCode)
                }
            }

            if !site.labels.isEmpty {
                GlassCard {
                    HStack {
                        ForEach(site.labels) { label in
                            StatusPill(text: label.name, color: label.color?.hexColor ?? .gray)
                        }
                    }
                }
            }

            GlassSectionHeader(title: "Aktionen", systemImage: "bolt")
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    if site.isPending {
                        actionButton("Site freigeben", systemImage: "checkmark.seal", prominent: true) {
                            try await context.client.approveSite(site.siteId)
                        }
                        Button(role: .destructive) { confirmReject = true } label: {
                            Label("Ablehnen", systemImage: "xmark.seal").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                    if !site.isLocal {
                        actionButton("Neu starten", systemImage: "arrow.clockwise") {
                            try await context.client.restartSite(site.siteId)
                        }
                    }
                    Button {
                        newName = site.name
                        renaming = true
                    } label: {
                        Label("Umbenennen", systemImage: "pencil").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Site löschen", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .tint(.red)
                }
                .controlSize(.large)
            }
        }
        .navigationTitle(site.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
        .actionErrors(runner)
        .alert("Site umbenennen", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Abbrechen", role: .cancel) {}
            Button("Speichern") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task {
                    if await runner.run(success: "rename", { try await context.client.updateSite(site.siteId, UpdateSiteBody(name: name)) }) {
                        await reload()
                    }
                }
            }
        }
        .confirmationDialog("Site „\(site.name)“ löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Endgültig löschen", role: .destructive) {
                Task {
                    if await runner.run(success: "delete", { try await context.client.deleteSite(site.siteId) }) { dismiss() }
                }
            }
        } message: {
            Text("Die Site und alle zugehörigen Daten werden entfernt. Verbundene Ressourcen verlieren ihre Targets.")
        }
        .confirmationDialog("Site ablehnen?", isPresented: $confirmReject, titleVisibility: .visible) {
            Button("Ablehnen und löschen", role: .destructive) {
                Task {
                    if await runner.run(success: "reject", { try await context.client.rejectSite(site.siteId) }) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ title: String, systemImage: String, prominent: Bool = false,
                              _ action: @escaping () async throws -> Void) -> some View {
        let button = Button {
            Task {
                if await runner.run(success: title, action) { await reload() }
            }
        } label: {
            Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
        }
        if prominent {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private func reload() async {
        if let fresh = try? await context.client.site(site.siteId) {
            // The detail endpoint lacks list-only fields; keep them from the list row.
            var merged = fresh
            merged.labels = fresh.labels.isEmpty ? site.labels : fresh.labels
            merged.resourceCount = fresh.resourceCount ?? site.resourceCount
            merged.exitNodeName = fresh.exitNodeName ?? site.exitNodeName
            merged.newtUpdateAvailable = fresh.newtUpdateAvailable ?? site.newtUpdateAvailable
            site = merged
        }
    }
}
