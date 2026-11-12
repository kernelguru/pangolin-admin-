import SwiftUI
import PangolinKit

struct MoreView: View {
    let context: OrgContext
    @Environment(AppModel.self) private var model
    @State private var showsServers = false

    var body: some View {
        GlassScreen {
            GlassSectionHeader(title: "Organisation", systemImage: "building.2")
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    link("Benutzer", systemImage: "person.2", destination: .users)
                    link("Einladungen", systemImage: "envelope.open", destination: .invitations)
                    link("Rollen", systemImage: "person.badge.shield.checkmark", destination: .roles)
                    link("Domains", systemImage: "network", destination: .domains)
                    link("Protokolle", systemImage: "list.bullet.clipboard", destination: .logs)
                }
            }

            GlassSectionHeader(title: "Überwachung", systemImage: "waveform.path.ecg")
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    link("Health-Checks", systemImage: "waveform.path.ecg", destination: .healthChecks)
                    link("Alert-Regeln", systemImage: "bell.badge", destination: .alertRules)
                }
            }

            GlassSectionHeader(title: "Server", systemImage: "server.rack")
            link("Server-Update (SSH)", systemImage: "arrow.triangle.2.circlepath.circle", destination: .serverUpdate)

            GlassSectionHeader(title: "App", systemImage: "gearshape")
            Button {
                showsServers = true
            } label: {
                MenuRow(title: "Server & API-Schlüssel", subtitle: model.activeProfile?.host, systemImage: "server.rack")
            }
            .buttonStyle(.plain)
            link("Info", systemImage: "info.circle", destination: .about)
        }
        .navigationTitle("Mehr")
        .toolbar { OrgSwitcherToolbar() }
        .navigationDestination(for: MoreDestination.self) { destination in
            switch destination {
            case .users: UsersView(context: context)
            case .invitations: InvitationsView(context: context)
            case .roles: RolesView(context: context)
            case .domains: DomainsView(context: context)
            case .logs: LogsView(context: context)
            case .healthChecks: HealthChecksView(context: context)
            case .alertRules: AlertRulesView(context: context)
            case .serverUpdate: ServerUpdateView(context: context)
            case .about: AboutView()
            }
        }
        .sheet(isPresented: $showsServers) {
            NavigationStack { ServerListView() }
        }
    }

    private func link(_ title: String, systemImage: String, destination: MoreDestination) -> some View {
        NavigationLink(value: destination) {
            MenuRow(title: title, subtitle: nil, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

enum MoreDestination: Hashable {
    case users, invitations, roles, domains, logs, healthChecks, alertRules, serverUpdate, about
}

private struct MenuRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
    }
}

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        GlassScreen {
            GlassCard {
                VStack(spacing: 10) {
                    InfoRow(label: "Version", value: version)
                    InfoRow(label: "API", value: "Pangolin Integration API v1")
                }
            }
            GlassCard {
                Text("Diese App nutzt ausschließlich die Integration API eines selbst gehosteten Pangolin-Servers. API-Schlüssel werden nur in der Keychain dieses Geräts gespeichert. Die API ist laut Pangolin noch nicht stabil – nach Server-Updates können sich Felder ändern.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Info")
    }
}
