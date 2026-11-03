import SwiftUI
import PangolinKit

struct MainTabView: View {
    let context: OrgContext

    var body: some View {
        TabView {
            Tab("Übersicht", systemImage: "gauge.with.dots.needle.67percent") {
                NavigationStack { DashboardView(context: context) }
            }
            Tab("Sites", systemImage: "server.rack") {
                NavigationStack { SitesView(context: context) }
            }
            Tab("Ressourcen", systemImage: "globe") {
                NavigationStack { ResourcesView(context: context) }
            }
            Tab("Clients", systemImage: "laptopcomputer.and.iphone") {
                NavigationStack { ClientsView(context: context) }
            }
            Tab("Mehr", systemImage: "ellipsis") {
                NavigationStack { MoreView(context: context) }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

/// Toolbar button showing the current organization; lets root keys switch orgs and opens server settings.
struct OrgSwitcherToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model
    @State private var showsServers = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                if model.organizations.count > 1 {
                    Section("Organisation") {
                        ForEach(model.organizations) { org in
                            Button {
                                model.selectedOrgId = org.orgId
                            } label: {
                                if org.orgId == model.selectedOrgId {
                                    Label(org.name, systemImage: "checkmark")
                                } else {
                                    Text(org.name)
                                }
                            }
                        }
                    }
                }
                Section(model.activeProfile?.name ?? "Server") {
                    Button("Server verwalten", systemImage: "server.rack") { showsServers = true }
                }
            } label: {
                Label(model.selectedOrganization?.name ?? model.selectedOrgId ?? "Organisation",
                      systemImage: "building.2")
            }
            .sheet(isPresented: $showsServers) {
                NavigationStack { ServerListView() }
            }
        }
    }
}
