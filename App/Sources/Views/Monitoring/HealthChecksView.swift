import SwiftUI
import PangolinKit

extension HealthCheck {
    var healthText: String {
        guard enabled else { return "Aus" }
        switch health {
        case "healthy": return "Gesund"
        case "unhealthy": return "Fehler"
        default: return "Unbekannt"
        }
    }

    var healthColor: Color {
        guard enabled else { return .gray }
        switch health {
        case "healthy": return .green
        case "unhealthy": return .red
        default: return .gray
        }
    }
}

struct HealthChecksView: View {
    let context: OrgContext

    @State private var state: Loadable<[HealthCheck]> = .idle
    @State private var search = ""
    @State private var showTargetChecks = false
    @State private var sheet: EditSheet<HealthCheck>?
    @State private var pendingDelete: HealthCheck?
    @State private var runner = ActionRunner()

    private var visible: [HealthCheck] {
        (state.value ?? []).filter { check in
            (showTargetChecks || !check.isTargetCheck)
                && (search.isEmpty || check.name.localizedCaseInsensitiveContains(search)
                    || (check.hostname ?? "").localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        GlassScreen {
            Toggle("Auch Target-Checks von Ressourcen zeigen", isOn: $showTargetChecks)
                .font(.callout)
                .padding(.horizontal, 6)

            switch state {
            case .idle, .loading:
                ProgressView().padding(.top, 60)
            case .failed(let message):
                GlassMessage(title: "Health-Checks nicht verfügbar", message: message,
                             systemImage: "waveform.path.ecg") { Task { await load() } }
            case .loaded:
                if visible.isEmpty {
                    GlassMessage(title: "Keine Health-Checks",
                                 message: "Health-Checks überwachen Hosts im Netz einer Site per HTTP, TCP oder Ping und können Alert-Regeln auslösen.",
                                 systemImage: "waveform.path.ecg")
                }
                ForEach(visible) { check in
                    HealthCheckRow(check: check)
                        .onTapGesture { if !check.isTargetCheck { sheet = .edit(check) } }
                        .contextMenu {
                            if !check.isTargetCheck {
                                Button("Bearbeiten", systemImage: "pencil") { sheet = .edit(check) }
                                Button(check.enabled ? "Deaktivieren" : "Aktivieren",
                                       systemImage: check.enabled ? "pause.circle" : "play.circle") {
                                    perform {
                                        try await context.client.updateHealthCheck(
                                            orgId: context.orgId, healthCheckId: check.id,
                                            HealthCheckBody(hcEnabled: !check.enabled))
                                    }
                                }
                                Button("Löschen", systemImage: "trash", role: .destructive) { pendingDelete = check }
                            }
                        }
                }
            }
        }
        .navigationTitle("Health-Checks")
        .searchable(text: $search, prompt: "Name oder Host")
        .refreshable { await load() }
        .task { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Neuer Health-Check", systemImage: "plus") { sheet = .new }
            }
        }
        .editorSheet(item: $sheet, onDismiss: { Task { await load() } }) { sheet in
            HealthCheckEditorView(context: context, check: sheet.value)
        }
        .confirmationDialog("Health-Check löschen?", isPresented: Binding(get: { pendingDelete != nil },
                                                                         set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { check in
            Button("„\(check.name)“ löschen", role: .destructive) {
                perform { try await context.client.deleteHealthCheck(orgId: context.orgId, healthCheckId: check.id) }
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
            let checks = try await context.client.healthChecks(orgId: context.orgId).items
            state = .loaded(checks.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        } catch is CancellationError {
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

private struct HealthCheckRow: View {
    let check: HealthCheck

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(check.healthColor.opacity(0.18))
                    Image(systemName: icon).foregroundStyle(check.healthColor)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.name).font(.headline).lineLimit(1)
                    Text(check.displayTarget).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    Text([check.siteName, check.resourceName.map { "Ressource: \($0)" },
                          check.interval.map { "alle \($0) s" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                StatusPill(text: check.healthText, color: check.healthColor)
            }
        }
        .opacity(check.enabled ? 1 : 0.6)
    }

    private var icon: String {
        switch check.mode {
        case "tcp": "cable.connector"
        case "ping": "dot.radiowaves.left.and.right"
        case "snmp": "chart.bar.doc.horizontal"
        default: "waveform.path.ecg"
        }
    }
}

struct HealthCheckEditorView: View {
    let context: OrgContext
    /// `nil` creates a new health check.
    let check: HealthCheck?

    @State private var name = ""
    @State private var siteId: Int?
    @State private var enabled = true
    @State private var mode: HealthCheckMode = .http
    @State private var hostname = ""
    @State private var port: Int?
    @State private var scheme = "http"
    @State private var path = ""
    @State private var method = "GET"
    @State private var expectedStatus: Int?
    @State private var followRedirects = true
    @State private var interval: Int? = 30
    @State private var unhealthyInterval: Int? = 30
    @State private var timeout: Int? = 5
    @State private var healthyThreshold: Int? = 1
    @State private var unhealthyThreshold: Int? = 1
    @State private var sites: [Site] = []
    @State private var didPopulate = false

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && siteId != nil
            && (!enabled || !hostname.trimmingCharacters(in: .whitespaces).isEmpty)
            && (mode == .ping || port != nil || mode == .http)
    }

    var body: some View {
        EditorSheet(title: check == nil ? "Neuer Health-Check" : "Health-Check", canSave: canSave, save: save) {
            Section {
                TextField("Name", text: $name)
                Picker("Site", selection: $siteId) {
                    Text("Bitte wählen").tag(Int?.none)
                    ForEach(sites) { Text($0.name).tag(Int?.some($0.siteId)) }
                }
                Toggle("Aktiv", isOn: $enabled)
            } footer: {
                Text("Der Check läuft im Netz der gewählten Site (über Newt).")
            }

            Section("Ziel") {
                Picker("Art", selection: $mode) {
                    Text("HTTP").tag(HealthCheckMode.http)
                    Text("TCP").tag(HealthCheckMode.tcp)
                    Text("Ping").tag(HealthCheckMode.ping)
                }
                .pickerStyle(.segmented)
                TextField("Host oder IP", text: $hostname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                if mode != .ping {
                    IntField(title: "Port", value: $port, prompt: mode == .http ? (scheme == "https" ? "443" : "80") : "z. B. 22")
                }
                if mode == .http {
                    Picker("Schema", selection: $scheme) {
                        Text("http").tag("http")
                        Text("https").tag("https")
                    }
                    TextField("Pfad", text: $path, prompt: Text("/health"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Methode", selection: $method) {
                        ForEach(["GET", "HEAD", "POST"], id: \.self) { Text($0).tag($0) }
                    }
                    IntField(title: "Erwarteter Status", value: $expectedStatus, prompt: "2xx")
                    Toggle("Weiterleitungen folgen", isOn: $followRedirects)
                }
            }

            Section("Zeitplan") {
                IntField(title: "Intervall (s)", value: $interval, prompt: "30")
                IntField(title: "Intervall bei Fehler (s)", value: $unhealthyInterval, prompt: "30")
                IntField(title: "Timeout (s)", value: $timeout, prompt: "5")
                IntField(title: "Gesund nach (Erfolge)", value: $healthyThreshold, prompt: "1")
                IntField(title: "Fehler nach (Fehlschläge)", value: $unhealthyThreshold, prompt: "1")
            }
        }
        .task {
            populate()
            sites = ((try? await context.client.allSites(orgId: context.orgId)) ?? []).filter { !$0.isPending }
            if siteId == nil { siteId = sites.first { $0.online == true }?.siteId ?? sites.first?.siteId }
        }
    }

    private func populate() {
        guard !didPopulate, let check else { return }
        didPopulate = true
        name = check.name
        siteId = check.siteId
        enabled = check.enabled
        mode = check.mode.flatMap(HealthCheckMode.init(rawValue:)) ?? .http
        hostname = check.hostname ?? ""
        port = check.port
        scheme = check.scheme ?? "http"
        path = check.path ?? ""
        method = check.method ?? "GET"
        expectedStatus = check.expectedStatus
        followRedirects = check.followRedirects ?? true
        interval = check.interval ?? 30
        unhealthyInterval = check.unhealthyInterval ?? 30
        timeout = check.timeout ?? 5
        healthyThreshold = check.healthyThreshold ?? 1
        unhealthyThreshold = check.unhealthyThreshold ?? 1
    }

    private func save() async throws {
        let isHTTP = mode == .http
        let host = hostname.trimmingCharacters(in: .whitespaces)
        let body = HealthCheckBody(
            name: name.trimmingCharacters(in: .whitespaces),
            siteId: siteId,
            hcEnabled: enabled,
            hcMode: mode,
            hcHostname: host.isEmpty ? nil : host,
            hcPort: mode == .ping ? nil : port,
            hcPath: isHTTP && !path.isEmpty ? path : nil,
            hcScheme: isHTTP ? scheme : nil,
            hcMethod: isHTTP ? method : nil,
            hcInterval: interval,
            hcUnhealthyInterval: unhealthyInterval,
            hcTimeout: timeout,
            hcStatus: isHTTP ? expectedStatus : nil,
            hcFollowRedirects: isHTTP ? followRedirects : nil,
            hcHealthyThreshold: healthyThreshold,
            hcUnhealthyThreshold: unhealthyThreshold
        )
        if let check {
            try await context.client.updateHealthCheck(orgId: context.orgId, healthCheckId: check.id, body)
        } else {
            try await context.client.createHealthCheck(orgId: context.orgId, body)
        }
    }
}
