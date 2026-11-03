import SwiftUI
import PangolinKit

struct DashboardSnapshot {
    var sites: [Site]
    var resources: [PublicResource]
    var clients: [Client]
    var deniedRequests: Int?
    var loadedAt: Date

    var sitesOnline: Int { sites.filter { $0.online == true }.count }
    var sitesOffline: [Site] { sites.filter { $0.online == false && !$0.isPending } }
    var pendingSites: [Site] { sites.filter(\.isPending) }
    var resourcesHealthy: Int { resources.filter { $0.enabled && $0.health == .healthy }.count }
    var problemResources: [PublicResource] {
        resources.filter { $0.enabled && ($0.health == .degraded || $0.health == .offline || $0.health == .unhealthy) }
    }
    var unprotectedResources: [PublicResource] {
        resources.filter { $0.enabled && $0.http != false && $0.fullDomain != nil && !$0.isProtected }
    }
    var clientsOnline: Int { clients.filter { $0.online == true }.count }
    var pendingClients: [Client] { clients.filter { $0.approvalState == "pending" } }
    var trafficIn: Double { sites.reduce(0) { $0 + ($1.megabytesIn ?? 0) } }
    var trafficOut: Double { sites.reduce(0) { $0 + ($1.megabytesOut ?? 0) } }
}

struct DashboardView: View {
    let context: OrgContext

    @State private var state: Loadable<DashboardSnapshot> = .idle
    @State private var runner = ActionRunner()
    /// Pangolin has no push/stream API, so the dashboard polls.
    private let refreshInterval: Duration = .seconds(30)

    var body: some View {
        GlassScreen {
            if let snapshot = state.value {
                content(snapshot)
            } else if case .failed(let message) = state {
                GlassMessage(title: "Laden fehlgeschlagen", message: message,
                             systemImage: "exclamationmark.icloud") { Task { await load() } }
            } else {
                ProgressView().padding(.top, 80)
            }
        }
        .navigationTitle("Übersicht")
        .navigationDestination(for: Site.self) { SiteDetailView(context: context, site: $0) }
        .navigationDestination(for: PublicResource.self) { ResourceDetailView(context: context, resource: $0) }
        .toolbar { OrgSwitcherToolbar() }
        .refreshable { await load() }
        .task(id: context) {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: refreshInterval)
            }
        }
        .actionErrors(runner)
    }

    @ViewBuilder
    private func content(_ s: DashboardSnapshot) -> some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                MetricTile(title: "Sites", value: "\(s.sitesOnline)/\(s.sites.count)",
                           detail: "online", systemImage: "server.rack",
                           tint: s.sitesOffline.isEmpty ? .green : .orange)
                MetricTile(title: "Ressourcen", value: "\(s.resourcesHealthy)/\(s.resources.count)",
                           detail: "gesund", systemImage: "globe",
                           tint: s.problemResources.isEmpty ? .green : .orange)
            }
            GridRow {
                MetricTile(title: "Clients", value: "\(s.clientsOnline)/\(s.clients.count)",
                           detail: "verbunden", systemImage: "laptopcomputer.and.iphone", tint: .blue)
                MetricTile(title: "Abgelehnt (24 h)", value: s.deniedRequests.map(String.init) ?? "–",
                           detail: "Anfragen", systemImage: "hand.raised", tint: .purple)
            }
        }

        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Datenverkehr (alle Sites)", systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
                HStack {
                    VStack(alignment: .leading) {
                        Text("Eingehend").font(.caption).foregroundStyle(.secondary)
                        Text(Format.traffic(s.trafficIn)).font(.title3.bold())
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Ausgehend").font(.caption).foregroundStyle(.secondary)
                        Text(Format.traffic(s.trafficOut)).font(.title3.bold())
                    }
                }
                TrafficBar(sites: s.sites)
            }
        }

        if !s.pendingSites.isEmpty {
            GlassSectionHeader(title: "Freigabe ausstehend", systemImage: "hourglass")
            ForEach(s.pendingSites) { site in
                GlassCard(tint: .orange) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(site.name).font(.headline)
                            Text(site.typeText).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Freigeben") {
                            Task {
                                await runner.run(success: "approved") { try await context.client.approveSite(site.siteId) }
                                await load()
                            }
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
            }
        }

        if !s.sitesOffline.isEmpty || !s.problemResources.isEmpty {
            GlassSectionHeader(title: "Probleme", systemImage: "exclamationmark.triangle")
            ForEach(s.sitesOffline) { site in
                NavigationLink(value: site) {
                    ProblemRow(title: site.name, subtitle: "Site offline", color: .red, systemImage: "server.rack")
                }
                .buttonStyle(.plain)
            }
            ForEach(s.problemResources) { resource in
                NavigationLink(value: resource) {
                    ProblemRow(title: resource.name, subtitle: "Ressource \(resource.healthText.lowercased())",
                               color: resource.healthColor, systemImage: "globe")
                }
                .buttonStyle(.plain)
            }
        }

        if !s.unprotectedResources.isEmpty {
            GlassSectionHeader(title: "Ohne Authentifizierung", systemImage: "lock.open")
            ForEach(s.unprotectedResources) { resource in
                NavigationLink(value: resource) {
                    ProblemRow(title: resource.name, subtitle: resource.displayAddress, color: .yellow,
                               systemImage: "lock.open")
                }
                .buttonStyle(.plain)
            }
        }

        Text("Aktualisiert \(Format.relative(s.loadedAt)) · alle 30 s")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func load() async {
        if state.value == nil { state = .loading }
        let client = context.client
        let orgId = context.orgId
        do {
            async let sites = client.allSites(orgId: orgId)
            async let resources = client.allResources(orgId: orgId)
            async let clients = client.allClients(orgId: orgId)
            // Logs need an extra permission – a missing permission must not break the dashboard.
            let deniedQuery = LogQuery(start: Date().addingTimeInterval(-86_400), end: Date(), limit: 1, allowed: false)
            let loaded = try await (sites, resources, clients)
            let denied = try? await client.requestLogs(orgId: orgId, deniedQuery).total
            let snapshot = DashboardSnapshot(sites: loaded.0, resources: loaded.1, clients: loaded.2,
                                             deniedRequests: denied, loadedAt: Date())
            withAnimation(.smooth) { state = .loaded(snapshot) }
        } catch is CancellationError {
            return
        } catch {
            if state.value == nil { state = .failed(error.localizedDescription) }
        }
    }
}

private struct ProblemRow: View {
    let title: String
    let subtitle: String
    let color: Color
    let systemImage: String

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
    }
}

/// Stacked bar showing each site's share of total traffic.
private struct TrafficBar: View {
    let sites: [Site]
    private let colors: [Color] = [.blue, .purple, .teal, .pink, .orange, .indigo, .mint, .cyan]

    var body: some View {
        let top = sites.filter { $0.totalMegabytes > 0 }.sorted { $0.totalMegabytes > $1.totalMegabytes }.prefix(colors.count)
        let total = max(top.reduce(0) { $0 + $1.totalMegabytes }, 1)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, site in
                        Capsule()
                            .fill(colors[index].gradient)
                            .frame(width: max(4, proxy.size.width * CGFloat(site.totalMegabytes / total) - 2))
                    }
                }
            }
            .frame(height: 10)
            FlowLegend(items: top.enumerated().map { ($0.element.name, colors[$0.offset]) })
        }
        .opacity(top.isEmpty ? 0 : 1)
    }
}

private struct FlowLegend: View {
    let items: [(String, Color)]

    var body: some View {
        ViewThatFits {
            HStack(spacing: 10) { entries }
            VStack(alignment: .leading, spacing: 4) { entries }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var entries: some View {
        ForEach(items.indices, id: \.self) { index in
            HStack(spacing: 4) {
                Circle().fill(items[index].1).frame(width: 6, height: 6)
                Text(items[index].0).lineLimit(1)
            }
        }
    }
}
