import SwiftUI
import PangolinKit

/// Which authentication method is being edited.
enum ResourceAuthKind: String, Identifiable {
    case password, pincode, headerAuth
    var id: String { rawValue }

    var title: String {
        switch self {
        case .password: "Passwort"
        case .pincode: "PIN-Code"
        case .headerAuth: "Header-Authentifizierung"
        }
    }
}

/// Sets or removes a password, PIN or header auth on a resource.
/// Pangolin never returns existing secrets, so the fields always start empty.
struct ResourceAuthEditor: View {
    let context: OrgContext
    let resource: PublicResource
    let kind: ResourceAuthKind

    @State private var secret = ""
    @State private var confirmation = ""
    @State private var headerUser = ""
    @State private var extendedCompatibility = false
    @State private var reveal = false
    @State private var confirmRemove = false
    @State private var runner = ActionRunner()
    @Environment(\.dismiss) private var dismiss

    private var isSet: Bool {
        switch kind {
        case .password: resource.passwordId != nil
        case .pincode: resource.pincodeId != nil
        case .headerAuth: resource.headerAuthId != nil
        }
    }

    private var validationMessage: String? {
        switch kind {
        case .password:
            if secret.isEmpty { return nil }
            if !PangolinValidation.isValidPassword(secret) { return "4 bis 100 Zeichen." }
            if secret != confirmation { return "Die Eingaben stimmen nicht überein." }
        case .pincode:
            if secret.isEmpty { return nil }
            if !PangolinValidation.isValidPincode(secret) { return "Genau 6 Ziffern." }
        case .headerAuth:
            if secret.isEmpty && headerUser.isEmpty { return nil }
            if !PangolinValidation.isValidPassword(headerUser) { return "Benutzername: 4 bis 100 Zeichen." }
            if !PangolinValidation.isValidPassword(secret) { return "Passwort: 4 bis 100 Zeichen." }
        }
        return nil
    }

    private var canSave: Bool {
        guard validationMessage == nil else { return false }
        switch kind {
        case .password: return !secret.isEmpty
        case .pincode: return !secret.isEmpty
        case .headerAuth: return !secret.isEmpty && !headerUser.isEmpty
        }
    }

    var body: some View {
        EditorSheet(title: kind.title, saveTitle: isSet ? "Ersetzen" : "Setzen", canSave: canSave, save: save) {
            Section {
                LabeledContent("Status", value: isSet ? "Aktiv" : "Nicht gesetzt")
            } footer: {
                Text(footer)
            }

            Section {
                switch kind {
                case .password:
                    secretField("Neues Passwort", text: $secret)
                    secretField("Wiederholen", text: $confirmation)
                case .pincode:
                    secretField("6-stelliger PIN", text: $secret)
                        .keyboardType(.numberPad)
                case .headerAuth:
                    TextField("Benutzername", text: $headerUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    secretField("Passwort", text: $secret)
                    Toggle("Erweiterte Kompatibilität", isOn: $extendedCompatibility)
                }
                Toggle("Eingabe anzeigen", isOn: $reveal)
            } footer: {
                if let validationMessage {
                    Text(validationMessage).foregroundStyle(.red)
                }
            }

            if isSet {
                Section {
                    Button("\(kind.title) entfernen", role: .destructive) { confirmRemove = true }
                }
            }
        }
        .confirmationDialog("\(kind.title) entfernen?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) {
                Task {
                    if await runner.run(success: "remove", remove) { dismiss() }
                }
            }
        }
        .actionErrors(runner)
    }

    private var footer: String {
        switch kind {
        case .password:
            "Besucher müssen dieses Passwort eingeben, bevor sie die Ressource erreichen."
        case .pincode:
            "Besucher müssen diesen 6-stelligen PIN eingeben."
        case .headerAuth:
            "Clients authentifizieren sich per HTTP-Basic-Auth-Header – praktisch für Skripte und Apps ohne Browser-Login."
        }
    }

    @ViewBuilder
    private func secretField(_ title: String, text: Binding<String>) -> some View {
        Group {
            if reveal {
                TextField(title, text: text)
            } else {
                SecureField(title, text: text)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .textContentType(.newPassword)
    }

    private func save() async throws {
        switch kind {
        case .password:
            try await context.client.setResourcePassword(resource.resourceId, password: secret)
        case .pincode:
            try await context.client.setResourcePincode(resource.resourceId, pincode: secret)
        case .headerAuth:
            try await context.client.setResourceHeaderAuth(
                resource.resourceId,
                SetHeaderAuthBody(user: headerUser, password: secret, extendedCompatibility: extendedCompatibility))
        }
    }

    private func remove() async throws {
        switch kind {
        case .password:
            try await context.client.setResourcePassword(resource.resourceId, password: nil)
        case .pincode:
            try await context.client.setResourcePincode(resource.resourceId, pincode: nil)
        case .headerAuth:
            try await context.client.setResourceHeaderAuth(resource.resourceId, .remove)
        }
    }
}

// MARK: - Rules

extension RuleAction {
    var title: String {
        switch self {
        case .accept: "Erlauben (ohne Login)"
        case .drop: "Blockieren"
        case .pass: "Weiter zur Anmeldung"
        }
    }

    var shortTitle: String {
        switch self {
        case .accept: "Erlauben"
        case .drop: "Blockieren"
        case .pass: "Weiter"
        }
    }

    var color: Color {
        switch self {
        case .accept: .green
        case .drop: .red
        case .pass: .blue
        }
    }
}

extension RuleMatch {
    var title: String {
        switch self {
        case .cidr: "IP-Bereich (CIDR)"
        case .ip: "IP-Adresse"
        case .path: "Pfad"
        case .country: "Land ist"
        case .countryIsNot: "Land ist nicht"
        case .asn: "ASN"
        case .region: "Region"
        case .method: "HTTP-Methode"
        }
    }

    var placeholder: String {
        switch self {
        case .cidr: "10.0.0.0/8"
        case .ip: "203.0.113.7"
        case .path: "/api/*"
        case .country, .countryIsNot: "DE"
        case .asn: "AS3320"
        case .region: "DE-BY"
        case .method: "GET"
        }
    }
}

/// Creates or edits a resource rule.
struct RuleEditorView: View {
    let context: OrgContext
    let resourceId: Int
    /// `nil` creates a new rule.
    let rule: ResourceRule?
    /// Suggested priority for new rules (after the last existing one).
    var nextPriority: Int = 100

    @State private var action: RuleAction = .accept
    @State private var match: RuleMatch = .cidr
    @State private var value = ""
    @State private var priority: Int? = nil
    @State private var enabled = true
    @State private var didPopulate = false

    private var canSave: Bool {
        !value.trimmingCharacters(in: .whitespaces).isEmpty && priority != nil
    }

    var body: some View {
        EditorSheet(title: rule == nil ? "Neue Regel" : "Regel bearbeiten", canSave: canSave, save: save) {
            Section {
                Picker("Aktion", selection: $action) {
                    ForEach(RuleAction.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Bedingung", selection: $match) {
                    ForEach(RuleMatch.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField(match.placeholder, text: $value)
                    .textInputAutocapitalization(match == .country || match == .countryIsNot || match == .method
                                                 ? .characters : .never)
                    .autocorrectionDisabled()
            } footer: {
                Text("Regeln werden nach Priorität (aufsteigend) geprüft; die erste passende gewinnt. Sie wirken nur, wenn „Regeln anwenden“ an der Ressource aktiv ist.")
            }
            Section {
                IntField(title: "Priorität", value: $priority, prompt: "\(nextPriority)")
                Toggle("Aktiv", isOn: $enabled)
            }
        }
        .onAppear {
            guard !didPopulate else { return }
            didPopulate = true
            if let rule {
                action = rule.action ?? .accept
                match = rule.match ?? .cidr
                value = rule.value
                priority = rule.priority
                enabled = rule.enabled
            } else {
                priority = nextPriority
            }
        }
    }

    private func save() async throws {
        let body = RuleBody(action: action, match: match, value: value.trimmingCharacters(in: .whitespaces),
                            priority: priority ?? nextPriority, enabled: enabled)
        if let rule {
            try await context.client.updateRule(resourceId: resourceId, ruleId: rule.ruleId, body)
        } else {
            try await context.client.createRule(resourceId: resourceId, body)
        }
    }
}
