import SwiftUI
import PangolinKit

struct ResourceDetailView: View {
    let context: OrgContext
    @State var resource: PublicResource

    @Environment(\.dismiss) private var dismiss
    @State private var targets: Loadable<[Target]> = .idle
    @State private var runner = ActionRunner()
    @State private var confirmDelete = false
    @State private var targetToDelete: Target?
    @State private var rules: Loadable<[ResourceRule]> = .idle
    @State private var ruleToDelete: ResourceRule?
    @State private var targetSheet: EditSheet<Target>?
    @State private var ruleSheet: EditSheet<ResourceRule>?
    @State private var authSheet: ResourceAuthKind?

    var body: some View {
        GlassScreen {
            GlassCard(tint: resource.healthColor) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StatusPill(text: resource.healthText, color: resource.healthColor)
                        Spacer()
                        Text((resource.mode ?? resource.protocolName ?? "http").uppercased())
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(resource.name).font(.title2.bold())
                    if let domain = resource.fullDomain, let url = URL(string: "https://\(domain)") {
                        Link(destination: url) {
                            Label(resource.displayAddress, systemImage: "safari")
                                .font(.callout)
                        }
                    } else {
                        Text(resource.displayAddress).font(.callout.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }

            GlassSectionHeader(title: "Zugriff", systemImage: "lock.shield")
            GlassCard {
                VStack(spacing: 12) {
                    toggle("Aktiviert", systemImage: "power", value: resource.enabled) { value in
                        UpdateResourceBody(enabled: value)
                    }
                    Divider()
                    toggle("Pangolin-SSO", systemImage: "person.badge.key", value: resource.sso ?? false) { value in
                        UpdateResourceBody(sso: value)
                    }
                    toggle("E-Mail-Whitelist", systemImage: "envelope.badge.shield.half.filled",
                           value: resource.whitelist ?? false) { value in
                        UpdateResourceBody(emailWhitelistEnabled: value)
                    }
                    toggle("Regeln anwenden", systemImage: "list.bullet.rectangle", value: resource.applyRules ?? false) { value in
                        UpdateResourceBody(applyRules: value)
                    }
                    toggle("Zugriff blockieren", systemImage: "hand.raised", value: resource.blockAccess ?? false) { value in
                        UpdateResourceBody(blockAccess: value)
                    }
                    Divider()
                    authRow(.password, systemImage: "key", isSet: resource.passwordId != nil)
                    authRow(.pincode, systemImage: "circle.grid.3x3", isSet: resource.pincodeId != nil)
                    authRow(.headerAuth, systemImage: "rectangle.and.text.magnifyingglass", isSet: resource.headerAuthId != nil)
                    InfoRow(label: "mTLS", value: resource.mtls == true ? "Aktiv" : "Nein")
                }
            }

            sectionHeader("Targets", systemImage: "scope") { targetSheet = .new }
            switch targets {
            case .idle, .loading:
                ProgressView()
            case .failed(let message):
                GlassMessage(title: "Targets nicht verfügbar", message: message, systemImage: "scope") {
                    Task { await loadTargets() }
                }
            case .loaded(let list):
                if list.isEmpty {
                    GlassMessage(title: "Keine Targets", systemImage: "scope")
                }
                ForEach(list) { target in
                    TargetRow(target: target, onEdit: { targetSheet = .edit(target) }) { enabled in
                        Task {
                            var body = UpdateTargetBody(target: target)
                            body.enabled = enabled
                            await runner.run(success: "target") { try await context.client.updateTarget(target.targetId, body) }
                            await loadTargets()
                        }
                    }
                    .contextMenu {
                        Button("Bearbeiten", systemImage: "pencil") { targetSheet = .edit(target) }
                        Button("Target löschen", systemImage: "trash", role: .destructive) { targetToDelete = target }
                    }
                }
            }

            Group {
                sectionHeader("Regeln", systemImage: "list.bullet.rectangle") { ruleSheet = .new }
                rulesSection
            }

            GlassSectionHeader(title: "Details", systemImage: "info.circle")
            GlassCard {
                VStack(spacing: 10) {
                    InfoRow(label: "ID", value: resource.niceId, monospaced: true)
                    InfoRow(label: "SSL", value: resource.ssl.map { $0 ? "Ja" : "Nein" })
                    InfoRow(label: "Port", value: resource.proxyPort.map(String.init))
                    InfoRow(label: "Load Balancing", value: resource.loadBalancingStrategy)
                    InfoRow(label: "Sticky Sessions", value: resource.stickySession.map { $0 ? "Ja" : "Nein" })
                    InfoRow(label: "Sites", value: resource.sites.map(\.siteName).joined(separator: ", "))
                }
            }

            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Ressource löschen", systemImage: "trash").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .tint(.red)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .navigationTitle(resource.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
        .actionErrors(runner)
        .confirmationDialog("Ressource „\(resource.name)“ löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Endgültig löschen", role: .destructive) {
                Task {
                    if await runner.run(success: "delete", { try await context.client.deleteResource(resource.resourceId) }) {
                        dismiss()
                    }
                }
            }
        }
        .confirmationDialog("Target löschen?", isPresented: Binding(get: { targetToDelete != nil },
                                                                   set: { if !$0 { targetToDelete = nil } }),
                            titleVisibility: .visible, presenting: targetToDelete) { target in
            Button("\(target.ip):\(target.port) löschen", role: .destructive) {
                Task {
                    await runner.run(success: "delete-target") { try await context.client.deleteTarget(target.targetId) }
                    await loadTargets()
                }
            }
        }
        .confirmationDialog("Regel löschen?", isPresented: Binding(get: { ruleToDelete != nil },
                                                                  set: { if !$0 { ruleToDelete = nil } }),
                            titleVisibility: .visible, presenting: ruleToDelete) { rule in
            Button("Regel „\(rule.value)“ löschen", role: .destructive) {
                Task {
                    await runner.run(success: "delete-rule") {
                        try await context.client.deleteRule(resourceId: resource.resourceId, ruleId: rule.ruleId)
                    }
                    await loadRules()
                }
            }
        }
        .editorSheet(item: $targetSheet, onDismiss: { Task { await loadTargets() } }) { sheet in
            TargetEditorView(context: context, resource: resource, target: sheet.value)
        }
        .editorSheet(item: $ruleSheet, onDismiss: { Task { await loadRules() } }) { sheet in
            RuleEditorView(context: context, resourceId: resource.resourceId, rule: sheet.value,
                           nextPriority: ((rules.value ?? []).map(\.priority).max() ?? 0) + 10)
        }
        .editorSheet(item: $authSheet, onDismiss: { Task { await reload() } }) { kind in
            ResourceAuthEditor(context: context, resource: resource, kind: kind)
        }
    }

    // MARK: Sections

    private func sectionHeader(_ title: String, systemImage: String, add: @escaping () -> Void) -> some View {
        HStack {
            GlassSectionHeader(title: title, systemImage: systemImage)
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("\(title) hinzufügen")
            .padding(.top, 8)
        }
    }

    private func authRow(_ kind: ResourceAuthKind, systemImage: String, isSet: Bool) -> some View {
        Button {
            authSheet = kind
        } label: {
            HStack {
                Label(kind.title, systemImage: systemImage)
                Spacer()
                Text(isSet ? "Gesetzt" : "Aus")
                    .foregroundStyle(isSet ? Color.green : Color.secondary)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var rulesSection: some View {
        switch rules {
        case .idle, .loading:
            ProgressView()
        case .failed(let message):
            GlassMessage(title: "Regeln nicht verfügbar", message: message, systemImage: "list.bullet.rectangle") {
                Task { await loadRules() }
            }
        case .loaded(let list):
            if resource.applyRules != true && !list.isEmpty {
                Label("„Regeln anwenden“ ist aus – die Regeln sind derzeit wirkungslos.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
            }
            if list.isEmpty {
                GlassMessage(title: "Keine Regeln",
                             message: "Mit Regeln lassen sich z. B. interne IP-Bereiche ohne Login erlauben oder Länder blockieren.",
                             systemImage: "list.bullet.rectangle")
            }
            ForEach(list) { rule in
                RuleRow(rule: rule)
                    .onTapGesture { ruleSheet = .edit(rule) }
                    .contextMenu {
                        Button("Bearbeiten", systemImage: "pencil") { ruleSheet = .edit(rule) }
                        Button(rule.enabled ? "Deaktivieren" : "Aktivieren",
                               systemImage: rule.enabled ? "pause.circle" : "play.circle") {
                            toggleRule(rule)
                        }
                        Button("Löschen", systemImage: "trash", role: .destructive) { ruleToDelete = rule }
                    }
            }
        }
    }

    private func toggleRule(_ rule: ResourceRule) {
        guard let action = rule.action, let match = rule.match else { return }
        Task {
            await runner.run(success: "toggle-rule") {
                try await context.client.updateRule(
                    resourceId: resource.resourceId, ruleId: rule.ruleId,
                    RuleBody(action: action, match: match, value: rule.value, priority: rule.priority,
                             enabled: !rule.enabled))
            }
            await loadRules()
        }
    }

    private func toggle(_ title: String, systemImage: String, value: Bool,
                        body makeBody: @escaping (Bool) -> UpdateResourceBody) -> some View {
        Toggle(isOn: Binding(
            get: { value },
            set: { newValue in
                Task {
                    let id = resource.resourceId
                    if await runner.run(success: title, { try await context.client.updateResource(id, makeBody(newValue)) }) {
                        await reload()
                    }
                }
            }
        )) {
            Label(title, systemImage: systemImage)
        }
        .disabled(runner.isRunning)
    }

    private func reload() async {
        let fresh = try? await context.client.resource(resource.resourceId)
        await loadTargets()
        await loadRules()
        if let fresh {
            var merged = fresh
            // Detail responses do not embed targets/sites/health.
            if merged.targets.isEmpty { merged.targets = resource.targets }
            if merged.sites.isEmpty { merged.sites = resource.sites }
            if merged.labels.isEmpty { merged.labels = resource.labels }
            merged.health = merged.health ?? resource.health
            merged.whitelist = merged.whitelist ?? resource.whitelist
            merged.mtls = merged.mtls ?? resource.mtls
            resource = merged
        }
    }

    private func loadTargets() async {
        if targets.value == nil { targets = .loading }
        do {
            targets = .loaded(try await context.client.targets(resourceId: resource.resourceId).items)
        } catch is CancellationError {
        } catch {
            targets = .failed(error.localizedDescription)
        }
    }
}

    private func loadRules() async {
        if rules.value == nil { rules = .loading }
        do {
            rules = .loaded(try await context.client.rules(resourceId: resource.resourceId).items)
        } catch is CancellationError {
        } catch {
            rules = .failed(error.localizedDescription)
        }
    }
}

/// Sheet state for "create new" vs. "edit existing".
enum EditSheet<Value: Identifiable>: Identifiable {
    case new
    case edit(Value)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let value): "edit-\(value.id)"
        }
    }

    var value: Value? {
        if case .edit(let value) = self { return value }
        return nil
    }
}

private struct RuleRow: View {
    let rule: ResourceRule

    var body: some View {
        GlassCard(tint: rule.enabled ? rule.action?.color : nil, padding: 12) {
            HStack(spacing: 12) {
                Text("\(rule.priority)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 32)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.value).font(.callout.monospaced()).lineLimit(1)
                    Text(rule.match?.title ?? rule.matchRaw).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: rule.action?.shortTitle ?? rule.actionRaw, color: rule.action?.color ?? .gray)
            }
        }
        .opacity(rule.enabled ? 1 : 0.5)
    }
}

private struct TargetRow: View {
    let target: Target
    var onEdit: () -> Void = {}
    let onToggle: (Bool) -> Void

    private var healthColor: Color {
        switch target.hcHealth {
        case "healthy": .green
        case "unhealthy": .red
        default: .gray
        }
    }

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Circle().fill(healthColor).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.displayAddress).font(.callout.monospaced()).lineLimit(1)
                        .onTapGesture(perform: onEdit)
                    Text([target.siteName, target.hcEnabled == true ? "Health-Check aktiv" : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Aktiv", isOn: Binding(get: { target.enabled }, set: onToggle))
                    .labelsHidden()
            }
        }
    }
}
