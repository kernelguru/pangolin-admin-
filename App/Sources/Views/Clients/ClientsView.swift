import SwiftUI
import PangolinKit

struct ClientsView: View {
    let context: OrgContext

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Alle", online = "Online", users = "Geräte", machines = "Maschinen",
             pending = "Ausstehend", blocked = "Gesperrt", archived = "Archiviert"
        var id: String { rawValue }
    }

    @State private var state: Loadable<[Client]> = .idle
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var runner = ActionRunner()
    @State private var pendingDelete: Client?

    private var visible: [Client] {
        (state.value ?? []).filter { c in
            let matchesFilter: Bool = switch filter {
            case .all: c.archived != true
            case .online: c.online == true
            case .users: !c.isMachine && c.archived != true
            case .machines: c.isMachine && c.archived != true
            case .pending: c.approvalState == "pending"
            case .blocked: c.blocked == true
            case .archived: c.archived == true
            }
            let matchesSearch = search.isEmpty
                || c.name.localizedCaseInsensitiveContains(search)
                || (c.username ?? "").localizedCaseInsensitiveContains(search)
                || (c.userEmail ?? "").localizedCaseInsensitiveContains(search)
                || (c.subnet ?? "").contains(search)
                || (c.hostname ?? "").localizedCaseInsensitiveContains(search)
            return matchesFilter && matchesSearch
        }
    }

    var body: some View {
        GlassScreen {
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases) { item in
                            Button(item.rawValue) { withAnimation(.smooth) { filter = item } }
                                .buttonStyle(.glass)
                                .tint(filter == item ? Color.accentColor : nil)
                                .fontWeight(filter == item ? .semibold : .regular)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            switch state {
            case .idle, .loading:
                ProgressView().padding(.top, 60)
            case .failed(let message):
                GlassMessage(title: "Clients konnten nicht geladen werden", message: message,
                             systemImage: "laptopcomputer.and.iphone") { Task { await load() } }
            case .loaded:
                if visible.isEmpty {
                    GlassMessage(title: "Keine Clients", systemImage: "laptopcomputer.and.iphone")
                }
                ForEach(visible) { client in
                    ClientRow(client: client)
                        .contextMenu { menu(for: client) }
                }
            }
        }
        .navigationTitle("Clients")
        .toolbar { OrgSwitcherToolbar() }
        .searchable(text: $search, prompt: "Name, Benutzer oder IP")
        .refreshable { await load() }
        .task(id: context) { await load() }
        .actionErrors(runner)
        .confirmationDialog("Client löschen?", isPresented: Binding(get: { pendingDelete != nil },
                                                                   set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { client in
            Button("„\(client.name)“ löschen", role: .destructive) {
                perform { try await context.client.deleteClient(client.clientId) }
            }
        }
    }

    @ViewBuilder
    private func menu(for client: Client) -> some View {
        if client.blocked == true {
            Button("Entsperren", systemImage: "lock.open") {
                perform { try await context.client.unblockClient(client.clientId) }
            }
        } else {
            Button("Sperren", systemImage: "hand.raised") {
                perform { try await context.client.blockClient(client.clientId) }
            }
        }
        if client.archived == true {
            Button("Wiederherstellen", systemImage: "tray.and.arrow.up") {
                perform { try await context.client.unarchiveClient(client.clientId) }
            }
        } else {
            Button("Archivieren", systemImage: "archivebox") {
                perform { try await context.client.archiveClient(client.clientId) }
            }
        }
        Button("Löschen", systemImage: "trash", role: .destructive) { pendingDelete = client }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            await runner.run(success: UUID().uuidString, operation)
            await load()
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let clients = try await context.client.allClients(orgId: context.orgId)
            state = .loaded(clients.sorted {
                if ($0.online == true) != ($1.online == true) { return $0.online == true }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            })
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct ClientRow: View {
    let client: Client

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(client.statusColor.opacity(0.18))
                        Image(systemName: client.isMachine ? "cpu" : "iphone.and.arrow.forward")
                            .foregroundStyle(client.statusColor)
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.name).font(.headline).lineLimit(1)
                        Text(client.isMachine ? "Maschinen-Client" : (client.username ?? client.userEmail ?? "Benutzergerät"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let device = client.deviceDescription {
                            Text(device)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    StatusPill(text: client.statusText, color: client.statusColor)
                }
                HStack {
                    Text(client.subnet ?? "–").font(.caption.monospaced())
                    if client.online != true, let lastSeen = client.lastSeen {
                        Text("· zuletzt \(Format.relative(lastSeen))").font(.caption2)
                    }
                    Spacer()
                    Text("↓ \(Format.traffic(client.megabytesIn))  ↑ \(Format.traffic(client.megabytesOut))")
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(.secondary)
                if !client.sites.isEmpty || !client.roles.isEmpty {
                    Text((client.sites.compactMap(\.siteName) + client.roles.map(\.name)).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .opacity(client.archived == true ? 0.6 : 1)
    }
}
