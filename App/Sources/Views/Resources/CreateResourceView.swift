import SwiftUI
import PangolinKit

/// Creates a public resource and, optionally, its first target in one step.
struct CreateResourceView: View {
    let context: OrgContext
    var onCreated: (PublicResource) -> Void = { _ in }

    enum Kind: String, CaseIterable, Identifiable {
        case http = "HTTP(S)", tcp = "TCP", udp = "UDP"
        var id: String { rawValue }
        var mode: ResourceMode {
            switch self {
            case .http: .http
            case .tcp: .tcp
            case .udp: .udp
            }
        }
    }

    @State private var name = ""
    @State private var kind: Kind = .http
    @State private var domains: [Domain] = []
    @State private var domainId: String?
    @State private var subdomain = ""
    @State private var proxyPort: Int?

    @State private var sites: [Site] = []
    @State private var addTarget = true
    @State private var target = TargetDraft()
    @State private var loadError: String?

    private var selectedDomain: Domain? { domains.first { $0.domainId == domainId } }

    private var previewAddress: String {
        switch kind {
        case .http:
            guard let base = selectedDomain?.baseDomain else { return "–" }
            let sub = subdomain.trimmingCharacters(in: .whitespaces)
            return "https://" + (sub.isEmpty ? base : "\(sub).\(base)")
        case .tcp, .udp:
            return "\(kind.rawValue.lowercased()):\(proxyPort.map(String.init) ?? "…")"
        }
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch kind {
        case .http: if domainId == nil { return false }
        case .tcp, .udp: guard let proxyPort, (1...65535).contains(proxyPort) else { return false }
        }
        return !addTarget || target.isValid
    }

    var body: some View {
        EditorSheet(title: "Neue Ressource", saveTitle: "Anlegen", canSave: canSave, save: save) {
            Section {
                TextField("Name", text: $name)
                Picker("Typ", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if kind == .http {
                Section {
                    Picker("Domain", selection: $domainId) {
                        Text("Bitte wählen").tag(String?.none)
                        ForEach(domains) { Text($0.baseDomain).tag(String?.some($0.domainId)) }
                    }
                    TextField("Subdomain (leer = Basisdomain)", text: $subdomain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Adresse")
                } footer: {
                    Text(previewAddress)
                }
            } else {
                Section {
                    IntField(title: "Öffentlicher Port", value: $proxyPort, prompt: "z. B. 2222")
                } header: {
                    Text("Port")
                } footer: {
                    Text("Raw-Ressourcen müssen auf dem Server mit `flags.allow_raw_resources: true` erlaubt sein und der Port muss in Gerbil/Traefik freigegeben werden.")
                }
            }

            Section {
                Toggle("Target gleich anlegen", isOn: $addTarget)
                if addTarget {
                    TargetFields(draft: $target, sites: sites, isHTTP: kind == .http)
                }
            } header: {
                Text("Ziel")
            }

            if let loadError {
                Section { Text(loadError).foregroundStyle(.red).font(.footnote) }
            }
        }
        .task { await loadOptions() }
    }

    private func loadOptions() async {
        do {
            async let d = context.client.domains(orgId: context.orgId).items
            async let s = context.client.allSites(orgId: context.orgId)
            let (loadedDomains, loadedSites) = try await (d, s)
            domains = loadedDomains.filter { $0.verified != false }
            sites = loadedSites.filter { !$0.isPending }
            if domainId == nil { domainId = domains.first?.domainId }
            if target.siteId == nil { target.siteId = sites.first { $0.online == true }?.siteId ?? sites.first?.siteId }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let body: CreateResourceBody = switch kind {
        case .http:
            .http(name: trimmedName, domainId: domainId ?? "",
                  subdomain: subdomain.trimmingCharacters(in: .whitespaces).lowercased())
        case .tcp, .udp:
            .raw(name: trimmedName, mode: kind.mode, proxyPort: proxyPort ?? 0)
        }
        let resource = try await context.client.createResource(orgId: context.orgId, body)
        if addTarget, let targetBody = target.createBody(isHTTP: kind == .http) {
            do {
                _ = try await context.client.createTarget(resourceId: resource.resourceId, targetBody)
            } catch {
                // The resource exists already; report the target problem but keep the resource.
                onCreated(resource)
                throw PangolinError.server(status: 0,
                                           message: "Ressource angelegt, Target fehlgeschlagen: \(error.localizedDescription)")
            }
        }
        onCreated(resource)
    }
}

// MARK: - Target form

/// Editable target values shared by the create-resource and target editor screens.
struct TargetDraft: Equatable {
    var siteId: Int?
    var method = "http"
    var ip = ""
    var port: Int?
    var enabled = true

    init() {}

    init(target: Target) {
        siteId = target.siteId
        method = target.method ?? "http"
        ip = target.ip
        port = target.port
        enabled = target.enabled
    }

    var isValid: Bool {
        siteId != nil && !ip.trimmingCharacters(in: .whitespaces).isEmpty
            && (port.map { (1...65535).contains($0) } ?? false)
    }

    func createBody(isHTTP: Bool) -> CreateTargetBody? {
        guard let siteId, let port, isValid else { return nil }
        return CreateTargetBody(siteId: siteId, ip: ip.trimmingCharacters(in: .whitespaces), port: port,
                                method: isHTTP ? method : nil, enabled: enabled)
    }

    func updateBody(isHTTP: Bool) -> UpdateTargetBody? {
        guard let siteId, let port, isValid else { return nil }
        return UpdateTargetBody(siteId: siteId, ip: ip.trimmingCharacters(in: .whitespaces), port: port,
                                method: isHTTP ? method : nil, enabled: enabled)
    }
}

struct TargetFields: View {
    @Binding var draft: TargetDraft
    let sites: [Site]
    let isHTTP: Bool

    var body: some View {
        Picker("Site", selection: $draft.siteId) {
            Text("Bitte wählen").tag(Int?.none)
            ForEach(sites) { site in
                Text(site.online == false ? "\(site.name) (offline)" : site.name).tag(Int?.some(site.siteId))
            }
        }
        if isHTTP {
            Picker("Protokoll", selection: $draft.method) {
                Text("http").tag("http")
                Text("https").tag("https")
                Text("h2c").tag("h2c")
            }
        }
        TextField("IP oder Hostname im Site-Netz", text: $draft.ip)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
        IntField(title: "Port", value: $draft.port, prompt: isHTTP ? "z. B. 8080" : "z. B. 22")
        Toggle("Aktiv", isOn: $draft.enabled)
    }
}

/// Creates or edits a single target of a resource.
struct TargetEditorView: View {
    let context: OrgContext
    let resource: PublicResource
    /// `nil` creates a new target.
    let target: Target?

    @State private var draft = TargetDraft()
    @State private var sites: [Site] = []

    private var isHTTP: Bool { resource.fullDomain != nil || (resource.mode ?? "http") == "http" }

    var body: some View {
        EditorSheet(title: target == nil ? "Neues Target" : "Target bearbeiten", canSave: draft.isValid, save: save) {
            Section {
                TargetFields(draft: $draft, sites: sites, isHTTP: isHTTP)
            } footer: {
                Text("Das Target muss vom Newt-Client der gewählten Site erreichbar sein.")
            }
        }
        .task {
            if let target, draft == TargetDraft() { draft = TargetDraft(target: target) }
            sites = ((try? await context.client.allSites(orgId: context.orgId)) ?? []).filter { !$0.isPending }
            if draft.siteId == nil { draft.siteId = resource.sites.first?.siteId ?? sites.first?.siteId }
        }
    }

    private func save() async throws {
        if let target {
            guard let body = draft.updateBody(isHTTP: isHTTP) else { return }
            try await context.client.updateTarget(target.targetId, body)
        } else {
            guard let body = draft.createBody(isHTTP: isHTTP) else { return }
            _ = try await context.client.createTarget(resourceId: resource.resourceId, body)
        }
    }
}
