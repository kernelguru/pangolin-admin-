import SwiftUI
import PangolinKit

struct SitesView: View {
    let context: OrgContext

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Alle", online = "Online", offline = "Offline", pending = "Ausstehend"
        var id: String { rawValue }
    }

    @State private var state: Loadable<[Site]> = .idle
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var runner = ActionRunner()

    private var visibleSites: [Site] {
        let sites = state.value ?? []
        return sites.filter { site in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .online: site.online == true
            case .offline: site.online == false && !site.isPending
            case .pending: site.isPending
            }
            let matchesSearch = search.isEmpty
                || site.name.localizedCaseInsensitiveContains(search)
                || site.niceId.localizedCaseInsensitiveContains(search)
                || (site.address ?? "").contains(search)
            return matchesFilter && matchesSearch
        }
    }

    var body: some View {
        GlassScreen {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)

            switch state {
            case .idle, .loading:
                ProgressView().padding(.top, 60)
            case .failed(let message):
                GlassMessage(title: "Sites konnten nicht geladen werden", message: message,
                             systemImage: "server.rack") { Task { await load() } }
            case .loaded:
                if visibleSites.isEmpty {
                    GlassMessage(title: "Keine Sites", message: search.isEmpty ? nil : "Keine Treffer für „\(search)“.",
                                 systemImage: "server.rack")
                }
                ForEach(visibleSites) { site in
                    NavigationLink(value: site) { SiteRow(site: site) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if !site.isLocal {
                                Button("Neu starten", systemImage: "arrow.clockwise") {
                                    Task { await runner.run(success: "restart") { try await context.client.restartSite(site.siteId) } }
                                }
                            }
                            if site.isPending {
                                Button("Freigeben", systemImage: "checkmark.seal") {
                                    Task {
                                        await runner.run(success: "approve") { try await context.client.approveSite(site.siteId) }
                                        await load()
                                    }
                                }
                            }
                        }
                }
            }
        }
        .navigationTitle("Sites")
        .toolbar { OrgSwitcherToolbar() }
        .searchable(text: $search, prompt: "Name, ID oder Adresse")
        .refreshable { await load() }
        .task(id: context) { await load() }
        .navigationDestination(for: Site.self) { SiteDetailView(context: context, site: $0) }
        .actionErrors(runner)
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let sites = try await context.client.allSites(orgId: context.orgId)
            state = .loaded(sites.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct SiteRow: View {
    let site: Site

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(site.statusColor.opacity(0.18))
                    Image(systemName: site.isLocal ? "house" : "server.rack")
                        .foregroundStyle(site.statusColor)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(site.name).font(.headline).lineLimit(1)
                        if site.newtUpdateAvailable == true {
                            Image(systemName: "arrow.up.circle.fill").foregroundStyle(.blue).imageScale(.small)
                        }
                    }
                    Text("\(site.typeText) · \(site.niceId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !site.isLocal {
                        Text("↓ \(Format.traffic(site.megabytesIn))  ↑ \(Format.traffic(site.megabytesOut))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                StatusPill(text: site.statusText, color: site.statusColor)
            }
        }
    }
}
