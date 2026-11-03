import SwiftUI

/// Lists saved servers; switch, edit or delete them.
struct ServerListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var editorMode: ServerEditorView.Mode?
    @State private var pendingDelete: ServerProfile?

    var body: some View {
        GlassScreen {
            ForEach(model.profiles) { profile in
                GlassCard(tint: profile.id == model.activeProfileID ? .accentColor : nil) {
                    HStack(spacing: 12) {
                        Image(systemName: profile.isRootKey ? "crown" : "building.2")
                            .font(.title3)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).font(.headline)
                            Text(profile.host).font(.caption).foregroundStyle(.secondary)
                            if !model.hasStoredKey(for: profile) {
                                Text("Kein Schlüssel gespeichert").font(.caption).foregroundStyle(.red)
                            }
                        }
                        Spacer()
                        if profile.id == model.activeProfileID {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                    .onTapGesture {
                        Task {
                            await model.connect(to: profile)
                            dismiss()
                        }
                    }
                }
                .contextMenu {
                    Button("Bearbeiten", systemImage: "pencil") { editorMode = .edit(profile) }
                    Button("Löschen", systemImage: "trash", role: .destructive) { pendingDelete = profile }
                }
            }

            Button {
                editorMode = .add
            } label: {
                Label("Server hinzufügen", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)

            Text("Lange drücken zum Bearbeiten oder Löschen. Beim Löschen wird auch der API-Schlüssel aus der Keychain entfernt.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
        }
        .navigationTitle("Server")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }
            }
        }
        .sheet(item: Binding(get: { editorMode.map(EditorItem.init) }, set: { editorMode = $0?.mode })) { item in
            NavigationStack { ServerEditorView(mode: item.mode) }
        }
        .confirmationDialog("Server löschen?", isPresented: Binding(get: { pendingDelete != nil },
                                                                     set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { profile in
            Button("„\(profile.name)“ löschen", role: .destructive) { model.delete(profile) }
        }
    }

    private struct EditorItem: Identifiable {
        let mode: ServerEditorView.Mode
        var id: String {
            switch mode {
            case .onboarding: "onboarding"
            case .add: "add"
            case .edit(let profile): profile.id.uuidString
            }
        }
    }
}
