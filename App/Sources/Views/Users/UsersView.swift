import SwiftUI
import PangolinKit

struct UsersView: View {
    let context: OrgContext

    @State private var users: Loadable<[OrgUser]> = .idle
    @State private var roles: [Role] = []
    @State private var search = ""
    @State private var runner = ActionRunner()
    @State private var pendingRemoval: OrgUser?
    @State private var showsInvite = false

    private var visible: [OrgUser] {
        (users.value ?? []).filter {
            search.isEmpty
                || $0.displayName.localizedCaseInsensitiveContains(search)
                || ($0.email ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        GlassScreen {
            switch users {
            case .idle, .loading:
                ProgressView().padding(.top, 60)
            case .failed(let message):
                GlassMessage(title: "Benutzer konnten nicht geladen werden", message: message,
                             systemImage: "person.2") { Task { await load() } }
            case .loaded:
                ForEach(visible) { user in
                    UserRow(user: user)
                        .contextMenu { menu(for: user) }
                }
            }
        }
        .navigationTitle("Benutzer")
        .searchable(text: $search, prompt: "Name oder E-Mail")
        .refreshable { await load() }
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Einladen", systemImage: "person.badge.plus") { showsInvite = true }
            }
        }
        .sheet(isPresented: $showsInvite) {
            NavigationStack { InviteUserView(context: context, roles: roles) }
        }
        .actionErrors(runner)
        .confirmationDialog("Benutzer entfernen?", isPresented: Binding(get: { pendingRemoval != nil },
                                                                       set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible, presenting: pendingRemoval) { user in
            Button("\(user.displayName) aus Organisation entfernen", role: .destructive) {
                perform { try await context.client.removeUser(orgId: context.orgId, userId: user.id) }
            }
        }
    }

    @ViewBuilder
    private func menu(for user: OrgUser) -> some View {
        let assigned = Set(user.roles.map(\.roleId))
        Menu("Rollen", systemImage: "person.badge.shield.checkmark") {
            ForEach(roles) { role in
                Button {
                    if assigned.contains(role.roleId) {
                        perform { try await context.client.removeRole(role.roleId, fromUser: user.id) }
                    } else {
                        perform { try await context.client.addRole(role.roleId, toUser: user.id) }
                    }
                } label: {
                    if assigned.contains(role.roleId) {
                        Label(role.name, systemImage: "checkmark")
                    } else {
                        Text(role.name)
                    }
                }
                .disabled(assigned.contains(role.roleId) && assigned.count == 1)
            }
        }
        if user.isOwner != true {
            Button("Aus Organisation entfernen", systemImage: "person.badge.minus", role: .destructive) {
                pendingRemoval = user
            }
        }
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        Task {
            await runner.run(success: UUID().uuidString, operation)
            await load()
        }
    }

    private func load() async {
        if users.value == nil { users = .loading }
        do {
            async let loadedUsers = context.client.allUsers(orgId: context.orgId)
            async let loadedRoles = context.client.allRoles(orgId: context.orgId)
            let (u, r) = try await (loadedUsers, loadedRoles)
            roles = r
            users = .loaded(u.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending })
        } catch is CancellationError {
        } catch {
            users = .failed(error.localizedDescription)
        }
    }
}

private struct UserRow: View {
    let user: OrgUser

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Text(String(user.displayName.prefix(1)).uppercased())
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.tint(.accentColor.opacity(0.3)), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(user.displayName).font(.headline).lineLimit(1)
                        if user.isOwner == true {
                            Image(systemName: "crown.fill").foregroundStyle(.yellow).imageScale(.small)
                        }
                    }
                    Text(user.email ?? user.username ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(user.roles.map(\.roleName).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if user.twoFactorEnabled == true {
                        StatusPill(text: "2FA", color: .green, systemImage: "checkmark.shield")
                    }
                    if let idp = user.idpName {
                        Text(idp).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct InviteUserView: View {
    let context: OrgContext
    let roles: [Role]

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var selectedRoles: Set<Int> = []
    @State private var validHours = 72
    @State private var sendEmail = true
    @State private var runner = ActionRunner()
    @State private var result: InviteResult?

    private var isValid: Bool { email.contains("@") && !selectedRoles.isEmpty }

    var body: some View {
        GlassScreen {
            if let result {
                GlassCard(tint: .green) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Einladung erstellt", systemImage: "checkmark.seal.fill").font(.headline)
                        Text(result.inviteLink).font(.caption.monospaced()).textSelection(.enabled)
                        if let url = URL(string: result.inviteLink) {
                            ShareLink(item: url) { Label("Link teilen", systemImage: "square.and.arrow.up") }
                                .buttonStyle(.glass)
                        }
                    }
                }
            } else {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("E-Mail-Adresse", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Stepper("Gültig: \(validHours) h", value: $validHours, in: 1...168, step: 12)
                        Toggle("E-Mail senden", isOn: $sendEmail)
                    }
                }
                GlassSectionHeader(title: "Rollen", systemImage: "person.badge.shield.checkmark")
                GlassCard {
                    VStack(spacing: 12) {
                        ForEach(roles) { role in
                            Toggle(role.name, isOn: Binding(
                                get: { selectedRoles.contains(role.roleId) },
                                set: { if $0 { selectedRoles.insert(role.roleId) } else { selectedRoles.remove(role.roleId) } }
                            ))
                        }
                        if roles.isEmpty { Text("Keine Rollen geladen").foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle("Benutzer einladen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(result == nil ? "Abbrechen" : "Fertig") { dismiss() }
            }
            if result == nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Senden") {
                        Task {
                            await runner.run(success: "invite") {
                                result = try await context.client.invite(
                                    orgId: context.orgId,
                                    CreateInviteBody(email: email.trimmingCharacters(in: .whitespaces),
                                                     roleIds: Array(selectedRoles), validHours: validHours,
                                                     sendEmail: sendEmail))
                            }
                        }
                    }
                    .disabled(!isValid || runner.isRunning)
                }
            }
        }
        .actionErrors(runner)
        .onAppear {
            if selectedRoles.isEmpty, let member = roles.first(where: { $0.isAdmin != true }) {
                selectedRoles = [member.roleId]
            }
        }
    }
}

struct InvitationsView: View {
    let context: OrgContext
    @State private var state: Loadable<[Invitation]> = .idle
    @State private var runner = ActionRunner()

    var body: some View {
        GlassScreen {
            switch state {
            case .idle, .loading:
                ProgressView().padding(.top, 60)
            case .failed(let message):
                GlassMessage(title: "Einladungen nicht verfügbar", message: message, systemImage: "envelope") {
                    Task { await load() }
                }
            case .loaded(let invitations):
                if invitations.isEmpty {
                    GlassMessage(title: "Keine offenen Einladungen", systemImage: "envelope.open")
                }
                ForEach(invitations) { invite in
                    GlassCard(padding: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invite.email).font(.headline)
                                Text(invite.roles.map(\.roleName).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let expires = invite.expiresAt {
                                    Text(expires < Date() ? "Abgelaufen" : "Läuft ab \(Format.relative(expires))")
                                        .font(.caption2)
                                        .foregroundStyle(expires < Date() ? Color.red : Color.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task {
                                    await runner.run(success: invite.inviteId) {
                                        try await context.client.deleteInvitation(orgId: context.orgId, inviteId: invite.inviteId)
                                    }
                                    await load()
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
            }
        }
        .navigationTitle("Einladungen")
        .refreshable { await load() }
        .task { await load() }
        .actionErrors(runner)
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await context.client.invitations(orgId: context.orgId).items)
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct RolesView: View {
    let context: OrgContext
    @State private var state: Loadable<[Role]> = .idle

    var body: some View {
        GlassScreen {
            switch state {
            case .idle, .loading:
                ProgressView().padding(.top, 60)
            case .failed(let message):
                GlassMessage(title: "Rollen nicht verfügbar", message: message, systemImage: "person.badge.shield.checkmark") {
                    Task { await load() }
                }
            case .loaded(let roles):
                ForEach(roles) { role in
                    GlassCard(padding: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(role.name).font(.headline)
                                if let description = role.description, !description.isEmpty {
                                    Text(description).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if role.isAdmin == true { StatusPill(text: "Admin", color: .orange) }
                            if role.requireDeviceApproval == true {
                                StatusPill(text: "Gerätefreigabe", color: .blue)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Rollen")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await context.client.allRoles(orgId: context.orgId))
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct DomainsView: View {
    let context: OrgContext
    @State private var state: Loadable<[Domain]> = .idle

    var body: some View {
        GlassScreen {
            switch state {
            case .idle, .loading:
                ProgressView().padding(.top, 60)
            case .failed(let message):
                GlassMessage(title: "Domains nicht verfügbar", message: message, systemImage: "network") {
                    Task { await load() }
                }
            case .loaded(let domains):
                ForEach(domains) { domain in
                    GlassCard(padding: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(domain.baseDomain).font(.headline)
                                Text([domain.type?.uppercased(), domain.certResolver].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let error = domain.errorMessage, !error.isEmpty {
                                    Text(error).font(.caption2).foregroundStyle(.red)
                                }
                            }
                            Spacer()
                            if domain.failed == true {
                                StatusPill(text: "Fehler", color: .red)
                            } else if domain.verified == true {
                                StatusPill(text: "Verifiziert", color: .green)
                            } else {
                                StatusPill(text: "Ausstehend", color: .orange)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Domains")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await context.client.domains(orgId: context.orgId).items)
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
