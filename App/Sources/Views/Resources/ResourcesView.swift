import SwiftUI
import UIKit
import PangolinKit

struct ResourcesView: View {
    let context: OrgContext

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Alle", problems = "Probleme", unprotected = "Offen", disabled = "Aus"
        var id: String { rawValue }
    }

    @State private var state: Loadable<[PublicResource]> = .idle
    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var runner = ActionRunner()

    private var visible: [PublicResource] {
        (state.value ?? []).filter { r in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .problems: r.enabled && (r.health == .degraded || r.health == .offline || r.health == .unhealthy)
            case .unprotected: r.enabled && !r.isProtected
            case .disabled: !r.enabled
            }
            let matchesSearch = search.isEmpty
                || r.name.localizedCaseInsensitiveContains(search)
                || (r.fullDomain ?? "").localizedCaseInsensitiveContains(search)
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
                GlassMessage(title: "Ressourcen konnten nicht geladen werden", message: message,
                             systemImage: "globe") { Task { await load() } }
            case .loaded:
                if visible.isEmpty {
                    GlassMessage(title: "Keine Ressourcen", systemImage: "globe")
                }
                ForEach(visible) { resource in
                    NavigationLink(value: resource) { ResourceRow(resource: resource) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(resource.enabled ? "Deaktivieren" : "Aktivieren",
                                   systemImage: resource.enabled ? "pause.circle" : "play.circle") {
                                Task {
                                    await runner.run(success: "toggle") {
                                        try await context.client.setResourceEnabled(resource.resourceId, enabled: !resource.enabled)
                                    }
                                    await load()
                                }
                            }
                            if let domain = resource.fullDomain, let url = URL(string: "https://\(domain)") {
                                Link(destination: url) { Label("Im Browser öffnen", systemImage: "safari") }
                                Button("Adresse kopieren", systemImage: "doc.on.doc") {
                                    UIPasteboard.general.string = url.absoluteString
                                }
                            }
                        }
                }
            }
        }
        .navigationTitle("Ressourcen")
        .toolbar { OrgSwitcherToolbar() }
        .searchable(text: $search, prompt: "Name oder Domain")
        .refreshable { await load() }
        .task(id: context) { await load() }
        .navigationDestination(for: PublicResource.self) { ResourceDetailView(context: context, resource: $0) }
        .actionErrors(runner)
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let resources = try await context.client.allResources(orgId: context.orgId)
            state = .loaded(resources.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct ResourceRow: View {
    let resource: PublicResource

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(resource.healthColor.opacity(0.18))
                    Image(systemName: resource.fullDomain != nil ? "globe" : "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(resource.healthColor)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(resource.name).font(.headline).lineLimit(1)
                        Image(systemName: resource.isProtected ? "lock.fill" : "lock.open")
                            .imageScale(.small)
                            .foregroundStyle(resource.isProtected ? Color.green : Color.yellow)
                    }
                    Text(resource.displayAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(resource.targets.count) Target(s) · \(resource.sites.map(\.siteName).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                StatusPill(text: resource.healthText, color: resource.healthColor)
            }
        }
        .opacity(resource.enabled ? 1 : 0.6)
    }
}
