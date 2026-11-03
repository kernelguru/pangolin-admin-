import SwiftUI
import PangolinKit

extension AlertEventType {
    var title: String {
        switch self {
        case .siteOnline: "Site online"
        case .siteOffline: "Site offline"
        case .siteToggle: "Site-Status ändert sich"
        case .healthCheckHealthy: "Health-Check gesund"
        case .healthCheckUnhealthy: "Health-Check fehlerhaft"
        case .healthCheckToggle: "Health-Check-Status ändert sich"
        case .resourceHealthy: "Ressource gesund"
        case .resourceUnhealthy: "Ressource offline"
        case .resourceDegraded: "Ressource eingeschränkt"
        case .resourceToggle: "Ressourcen-Status ändert sich"
        }
    }

    var systemImage: String {
        switch source {
        case .site: "server.rack"
        case .healthCheck: "waveform.path.ecg"
        case .resource: "globe"
        }
    }
}

struct AlertRulesView: View {
    let context: OrgContext

    @State private var state: Loadable<[AlertRule]> = .idle
    @State private var sheet: EditSheet<AlertRule>?
    @State private var pendingDelete: AlertRule?
    @State private var runner = ActionRunner()

    var body: some View {
        GlassScreen {
            switch state {
            case .idle, .loading:
                ProgressView().padding(.top, 60)
            case .failed(let message):
                GlassMessage(title: "Alert-Regeln nicht verfügbar", message: message,
                             systemImage: "bell.badge") { Task { await load() } }
            case .loaded(let rules):
                if rules.isEmpty {
                    GlassMessage(title: "Keine Alert-Regeln",
                                 message: "Lass dich per E-Mail oder Webhook benachrichtigen, wenn Sites offline gehen oder Health-Checks fehlschlagen.",
                                 systemImage: "bell.badge")
                }
                ForEach(rules) { rule in
                    AlertRuleRow(rule: rule)
                        .onTapGesture { sheet = .edit(rule) }
                        .contextMenu {
                            Button("Bearbeiten", systemImage: "pencil") { sheet = .edit(rule) }
                            Button(rule.enabled ? "Deaktivieren" : "Aktivieren",
                                   systemImage: rule.enabled ? "bell.slash" : "bell") {
                                perform {
                                    try await context.client.updateAlertRule(orgId: context.orgId, alertRuleId: rule.id,
                                                                             AlertRuleBody(enabled: !rule.enabled))
                                }
                            }
                            Button("Löschen", systemImage: "trash", role: .destructive) { pendingDelete = rule }
                        }
                }
            }
        }
        .navigationTitle("Alert-Regeln")
        .refreshable { await load() }
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Neue Alert-Regel", systemImage: "plus") { sheet = .new }
            }
        }
        .editorSheet(item: $sheet, onDismiss: { Task { await load() } }) { sheet in
            AlertRuleEditorView(context: context, existing: sheet.value)
        }
        .confirmationDialog("Alert-Regel löschen?", isPresented: Binding(get: { pendingDelete != nil },
                                                                        set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { rule in
            Button("„\(rule.name)“ löschen", role: .destructive) {
                perform { try await context.client.deleteAlertRule(orgId: context.orgId, alertRuleId: rule.id) }
            }
        }
        .actionErrors(runner)
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        Task {
            await runner.run(success: UUID().uuidString, operation)
            await load()
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await context.client.alertRules(orgId: context.orgId).items)
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct AlertRuleRow: View {
    let rule: AlertRule

    private var sourceText: String {
        switch rule.eventType?.source {
        case .site: rule.siteIds.isEmpty ? "Alle Sites" : "\(rule.siteIds.count) Site(s)"
        case .healthCheck: rule.healthCheckIds.isEmpty ? "Alle Health-Checks" : "\(rule.healthCheckIds.count) Health-Check(s)"
        case .resource: rule.resourceIds.isEmpty ? "Alle Ressourcen" : "\(rule.resourceIds.count) Ressource(n)"
        case .none: rule.eventTypeRaw
        }
    }

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.orange.opacity(rule.enabled ? 0.2 : 0.08))
                    Image(systemName: rule.eventType?.systemImage ?? "bell")
                        .foregroundStyle(rule.enabled ? Color.orange : Color.secondary)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name).font(.headline).lineLimit(1)
                    Text(rule.eventType?.title ?? rule.eventTypeRaw).font(.caption).foregroundStyle(.secondary)
                    Text([sourceText,
                          rule.cooldownSeconds > 0 ? "Pause \(rule.cooldownSeconds / 60) min" : nil,
                          rule.lastTriggeredAt.map { "zuletzt \(Format.relative($0))" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: rule.enabled ? "bell.fill" : "bell.slash")
                    .foregroundStyle(rule.enabled ? Color.orange : Color.secondary)
            }
        }
        .opacity(rule.enabled ? 1 : 0.6)
    }
}

/// Creates or edits an alert rule: event, sources, recipients and webhooks.
struct AlertRuleEditorView: View {
    let context: OrgContext
    let existing: AlertRule?

    @State private var name = ""
    @State private var eventType: AlertEventType = .siteOffline
    @State private var enabled = true
    @State private var cooldownMinutes: Int? = 5

    @State private var allSources = true
    @State private var selectedSites: Set<Int> = []
    @State private var selectedChecks: Set<Int> = []
    @State private var selectedResources: Set<Int> = []

    @State private var selectedUsers: Set<String> = []
    @State private var selectedRoles: Set<Int> = []
    @State private var emails: [String] = []
    @State private var newEmail = ""
    @State private var webhooks: [String] = []
    @State private var newWebhook = ""

    @State private var sites: [Site] = []
    @State private var checks: [HealthCheck] = []
    @State private var resources: [PublicResource] = []
    @State private var users: [OrgUser] = []
    @State private var roles: [Role] = []
    @State private var didPopulate = false
    @State private var loadError: String?

    private var body_: AlertRuleBody {
        let source = eventType.source
        return AlertRuleBody(
            name: name.trimmingCharacters(in: .whitespaces),
            eventType: eventType,
            enabled: enabled,
            cooldownSeconds: max(0, (cooldownMinutes ?? 0) * 60),
            siteIds: source == .site && !allSources ? Array(selectedSites) : (source == .site ? [] : nil),
            allSites: source == .site ? allSources : nil,
            healthCheckIds: source == .healthCheck && !allSources ? Array(selectedChecks) : (source == .healthCheck ? [] : nil),
            allHealthChecks: source == .healthCheck ? allSources : nil,
            resourceIds: source == .resource && !allSources ? Array(selectedResources) : (source == .resource ? [] : nil),
            allResources: source == .resource ? allSources : nil,
            userIds: Array(selectedUsers),
            roleIds: Array(selectedRoles),
            emails: emails,
            webhookActions: webhooks.map { WebhookActionBody(webhookUrl: $0) }
        )
    }

    private var validation: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Name fehlt." }
        return body_.validationError
    }

    var body: some View {
        EditorSheet(title: existing == nil ? "Neue Alert-Regel" : "Alert-Regel", canSave: validation == nil, save: save) {
            Section {
                TextField("Name", text: $name)
                Picker("Ereignis", selection: $eventType) {
                    ForEach(AlertEventType.allCases, id: \.self) { type in
                        Label(type.title, systemImage: type.systemImage).tag(type)
                    }
                }
                Toggle("Aktiv", isOn: $enabled)
                IntField(title: "Pause zwischen Alarmen (min)", value: $cooldownMinutes, prompt: "0")
            }

            Section {
                Toggle(allTitle, isOn: $allSources)
                if !allSources { sourcePicker }
            } header: {
                Text("Quelle")
            }

            Section("Empfänger") {
                if !users.isEmpty {
                    NavigationLink {
                        MultiSelectList(title: "Benutzer", items: users.map { SelectItem(id: $0.id, title: $0.displayName) },
                                        selection: $selectedUsers)
                    } label: {
                        LabeledContent("Benutzer", value: selectedUsers.isEmpty ? "Keine" : "\(selectedUsers.count)")
                    }
                }
                if !roles.isEmpty {
                    NavigationLink {
                        MultiSelectList(title: "Rollen", items: roles.map { SelectItem(id: $0.roleId, title: $0.name) }, selection: $selectedRoles)
                    } label: {
                        LabeledContent("Rollen", value: selectedRoles.isEmpty ? "Keine" : "\(selectedRoles.count)")
                    }
                }
                ForEach(emails, id: \.self) { email in
                    Label(email, systemImage: "envelope")
                }
                .onDelete { emails.remove(atOffsets: $0) }
                HStack {
                    TextField("E-Mail hinzufügen", text: $newEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addEmail)
                    Button("Hinzufügen", systemImage: "plus.circle.fill", action: addEmail)
                        .labelStyle(.iconOnly)
                        .disabled(!newEmail.contains("@"))
                }
            }

            Section {
                ForEach(webhooks, id: \.self) { url in
                    Label(url, systemImage: "link").lineLimit(1)
                }
                .onDelete { webhooks.remove(atOffsets: $0) }
                HStack {
                    TextField("https://…", text: $newWebhook)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addWebhook)
                    Button("Hinzufügen", systemImage: "plus.circle.fill", action: addWebhook)
                        .labelStyle(.iconOnly)
                        .disabled(URL(string: newWebhook)?.scheme?.hasPrefix("http") != true)
                }
            } header: {
                Text("Webhooks")
            } footer: {
                if existing != nil, !(existing?.webhookActions.isEmpty ?? true) {
                    Text("Beim Speichern werden die Webhooks durch diese Liste ersetzt. Authentifizierung von Webhooks lässt sich nur im Pangolin-Dashboard einstellen.")
                }
            }

            if let message = validation ?? (body_.hasNoRecipients ? "Hinweis: Ohne Empfänger löst die Regel keine Benachrichtigung aus." : nil) {
                Section { Text(message).font(.footnote).foregroundStyle(validation == nil ? Color.orange : Color.red) }
            }
            if let loadError {
                Section { Text(loadError).font(.footnote).foregroundStyle(.red) }
            }
        }
        .onChange(of: eventType) { old, new in
            if old.source != new.source { allSources = true }
        }
        .task { await loadOptions() }
    }

    private var allTitle: String {
        switch eventType.source {
        case .site: "Alle Sites"
        case .healthCheck: "Alle Health-Checks"
        case .resource: "Alle Ressourcen"
        }
    }

    @ViewBuilder
    private var sourcePicker: some View {
        switch eventType.source {
        case .site:
            ForEach(sites) { site in
                selectableRow(site.name, isOn: selectedSites.contains(site.siteId)) {
                    selectedSites.formSymmetricDifference([site.siteId])
                }
            }
        case .healthCheck:
            ForEach(checks) { check in
                selectableRow(check.name, isOn: selectedChecks.contains(check.id)) {
                    selectedChecks.formSymmetricDifference([check.id])
                }
            }
        case .resource:
            ForEach(resources) { resource in
                selectableRow(resource.name, isOn: selectedResources.contains(resource.resourceId)) {
                    selectedResources.formSymmetricDifference([resource.resourceId])
                }
            }
        }
    }

    private func selectableRow(_ title: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isOn { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }

    private func addEmail() {
        let value = newEmail.trimmingCharacters(in: .whitespaces).lowercased()
        guard value.contains("@"), !emails.contains(value) else { return }
        emails.append(value)
        newEmail = ""
    }

    private func addWebhook() {
        let value = newWebhook.trimmingCharacters(in: .whitespaces)
        guard URL(string: value)?.scheme?.hasPrefix("http") == true, !webhooks.contains(value) else { return }
        webhooks.append(value)
        newWebhook = ""
    }

    private func loadOptions() async {
        let client = context.client
        let orgId = context.orgId
        // Load everything independently so a missing permission only hides one picker.
        async let s = attempt { try await client.allSites(orgId: orgId) }
        async let c = attempt { try await client.healthChecks(orgId: orgId).items }
        async let r = attempt { try await client.allResources(orgId: orgId) }
        async let u = attempt { try await client.allUsers(orgId: orgId) }
        async let ro = attempt { try await client.allRoles(orgId: orgId) }
        sites = await s ?? []
        checks = await c ?? []
        resources = await r ?? []
        users = await u ?? []
        roles = await ro ?? []

        guard !didPopulate, let existing else { return }
        didPopulate = true
        // The list response lacks recipients and webhooks – fetch the full rule.
        let full: AlertRule
        do {
            full = try await client.alertRule(orgId: orgId, alertRuleId: existing.id)
        } catch {
            loadError = "Details konnten nicht geladen werden: \(error.localizedDescription)"
            full = existing
        }
        name = full.name
        eventType = full.eventType ?? .siteOffline
        enabled = full.enabled
        cooldownMinutes = full.cooldownSeconds / 60
        selectedSites = Set(full.siteIds)
        selectedChecks = Set(full.healthCheckIds)
        selectedResources = Set(full.resourceIds)
        switch eventType.source {
        case .site: allSources = full.allSites ?? full.siteIds.isEmpty
        case .healthCheck: allSources = full.allHealthChecks ?? full.healthCheckIds.isEmpty
        case .resource: allSources = full.allResources ?? full.resourceIds.isEmpty
        }
        selectedUsers = Set(full.recipients.compactMap(\.userId))
        selectedRoles = Set(full.recipients.compactMap(\.roleId))
        emails = full.recipients.compactMap(\.email)
        webhooks = full.webhookActions.map(\.webhookUrl)
    }

    private func save() async throws {
        if let existing {
            try await context.client.updateAlertRule(orgId: context.orgId, alertRuleId: existing.id, body_)
        } else {
            try await context.client.createAlertRule(orgId: context.orgId, body_)
        }
    }
}

/// Runs an operation and turns any error into `nil`.
private func attempt<T: Sendable>(_ operation: @Sendable () async throws -> T) async -> T? {
    try? await operation()
}

struct SelectItem<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
}

/// Checkmark list for picking several items.
struct MultiSelectList<ID: Hashable>: View {
    let title: String
    let items: [SelectItem<ID>]
    @Binding var selection: Set<ID>

    var body: some View {
        List {
            ForEach(items) { item in
                Button {
                    selection.formSymmetricDifference([item.id])
                } label: {
                    HStack {
                        Text(item.title).foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(item.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}
