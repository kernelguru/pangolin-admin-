import SwiftUI

@main
struct PangolinAdminApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.restore() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.profiles.isEmpty {
                NavigationStack {
                    ServerEditorView(mode: .onboarding)
                }
            } else if let context = model.context {
                MainTabView(context: context)
                    .id(context)
            } else {
                ConnectingView()
            }
        }
        .animation(.smooth, value: model.context)
    }
}

/// Shown while connecting, or when the active profile cannot be used.
struct ConnectingView: View {
    @Environment(AppModel.self) private var model
    @State private var showsServers = false

    var body: some View {
        NavigationStack {
            GlassScreen {
                Spacer(minLength: 120)
                if model.isConnecting {
                    GlassCard {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Verbinde mit \(model.activeProfile?.name ?? "Server") …")
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    GlassMessage(title: "Keine Verbindung",
                                 message: model.connectionError ?? "Bitte einen Server auswählen.",
                                 systemImage: "bolt.horizontal.circle") {
                        Task {
                            if let profile = model.activeProfile ?? model.profiles.first {
                                await model.connect(to: profile)
                            }
                        }
                    }
                    Button("Server verwalten") { showsServers = true }
                        .buttonStyle(.glass)
                }
            }
            .navigationTitle("Pangolin")
            .sheet(isPresented: $showsServers) {
                NavigationStack { ServerListView() }
            }
        }
    }
}
