import SwiftUI
import PangolinKit

enum Format {
    /// Pangolin reports traffic in megabytes.
    static func traffic(_ megabytes: Double?) -> String {
        guard let megabytes else { return "–" }
        let bytes = Int64((megabytes * 1_000_000).rounded())
        return bytes.formatted(.byteCount(style: .decimal))
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "–" }
        return date.formatted(.relative(presentation: .named))
    }

    static func dateTime(_ date: Date?) -> String {
        guard let date else { return "–" }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    static func dateString(_ value: String?) -> String {
        guard let value, let date = Date(pangolinString: value) else { return value ?? "–" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

extension Site {
    var statusText: String {
        if isPending { return "Ausstehend" }
        switch online {
        case .some(true): return "Online"
        case .some(false): return "Offline"
        case .none: return "Lokal"
        }
    }

    var statusColor: Color {
        if isPending { return .orange }
        switch online {
        case .some(true): return .green
        case .some(false): return .red
        case .none: return .blue
        }
    }

    var typeText: String {
        switch type {
        case "newt": "Newt"
        case "wireguard": "WireGuard"
        case "local": "Lokal"
        default: type ?? "–"
        }
    }
}

extension PublicResource {
    var healthText: String {
        if !enabled { return "Deaktiviert" }
        switch health {
        case .healthy: return "Gesund"
        case .degraded: return "Eingeschränkt"
        case .offline, .unhealthy: return "Offline"
        case .unknown, .none: return "Unbekannt"
        }
    }

    var healthColor: Color {
        if !enabled { return .gray }
        switch health {
        case .healthy: return .green
        case .degraded: return .orange
        case .offline, .unhealthy: return .red
        case .unknown, .none: return .gray
        }
    }
}

extension Client {
    var statusText: String {
        if blocked == true { return "Gesperrt" }
        if archived == true { return "Archiviert" }
        if approvalState == "pending" { return "Freigabe ausstehend" }
        return online == true ? "Online" : "Offline"
    }

    var statusColor: Color {
        if blocked == true { return .red }
        if archived == true { return .gray }
        if approvalState == "pending" { return .orange }
        return online == true ? .green : .secondary
    }
}

extension Client {
    /// „iOS 26.1 · iPhone18,1 · v1.2.0“
    var deviceDescription: String? {
        let platformName: String? = switch platform?.lowercased() {
        case "ios": "iOS"
        case "ipados": "iPadOS"
        case "macos": "macOS"
        case "windows": "Windows"
        case "android": "Android"
        case "linux": "Linux"
        case .some(let other): other
        case .none: nil
        }
        let system = [platformName, osVersion].compactMap { $0 }.joined(separator: " ")
        let version = (olmVersion ?? agentVersion).map { "v\($0)" }
        let parts = [system.isEmpty ? nil : system, deviceModel ?? hostname, version].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension String {
    /// `#ff0000` → Color
    var hexColor: Color? {
        var hex = trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}
