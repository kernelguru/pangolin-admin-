import SwiftUI
import PangolinKit

struct LogsView: View {
    let context: OrgContext

    enum Kind: String, CaseIterable, Identifiable {
        case requests = "Anfragen", access = "Zugriffe", actions = "Änderungen"
        var id: String { rawValue }
    }

    enum TimeRange: Int, CaseIterable, Identifiable {
        case hour = 1, day = 24, week = 168
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .hour: "1 h"
            case .day: "24 h"
            case .week: "7 Tage"
            }
        }
    }

    @State private var kind: Kind = .requests
    @State private var range: TimeRange = .day
    @State private var deniedOnly = false
    @State private var requests: [RequestLogEntry] = []
    @State private var access: [AccessLogEntry] = []
    @State private var actions: [ActionLogEntry] = []
    @State private var total = 0
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let pageSize = 100

    var body: some View {
        GlassScreen {
            VStack(spacing: 10) {
                Picker("Art", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Picker("Zeitraum", selection: $range) {
                        ForEach(TimeRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if kind == .requests {
                        Toggle("Nur abgelehnte", isOn: $deniedOnly)
                            .toggleStyle(.button)
                            .buttonStyle(.glass)
                    }
                }
            }
            .padding(.vertical, 4)

            if let errorMessage {
                GlassMessage(title: "Protokoll nicht verfügbar", message: errorMessage,
                             systemImage: "list.bullet.clipboard") { Task { await load(reset: true) } }
            } else if isLoading && currentCount == 0 {
                ProgressView().padding(.top, 60)
            } else if currentCount == 0 {
                GlassMessage(title: "Keine Einträge im Zeitraum", systemImage: "tray")
            }

            switch kind {
            case .requests: ForEach(requests) { RequestLogRow(entry: $0) }
            case .access: ForEach(access) { AccessLogRow(entry: $0) }
            case .actions: ForEach(actions) { ActionLogRow(entry: $0) }
            }

            if currentCount < total {
                Button {
                    Task { await load(reset: false) }
                } label: {
                    Label("Weitere laden (\(currentCount)/\(total))", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(isLoading)
            }
        }
        .navigationTitle("Protokolle")
        .refreshable { await load(reset: true) }
        .task(id: "\(kind.rawValue)-\(range.rawValue)-\(deniedOnly)") { await load(reset: true) }
    }

    private var currentCount: Int {
        switch kind {
        case .requests: requests.count
        case .access: access.count
        case .actions: actions.count
        }
    }

    private func load(reset: Bool) async {
        isLoading = true
        defer { isLoading = false }
        if reset {
            errorMessage = nil
            requests = []; access = []; actions = []; total = 0
        }
        var query = LogQuery.last(hours: range.rawValue, limit: pageSize)
        query.offset = reset ? 0 : currentCount
        do {
            switch kind {
            case .requests:
                if deniedOnly { query.allowed = false }
                let page = try await context.client.requestLogs(orgId: context.orgId, query)
                requests += page.items
                total = page.total
            case .access:
                let page = try await context.client.accessLogs(orgId: context.orgId, query)
                access += page.items
                total = page.total
            case .actions:
                let page = try await context.client.actionLogs(orgId: context.orgId, query)
                actions += page.items
                total = page.total
            }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RequestLogRow: View {
    let entry: RequestLogEntry

    var body: some View {
        GlassCard(tint: entry.allowed ? nil : Color.red, padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.method ?? "–").font(.caption.monospaced().bold())
                    Text(entry.resourceName ?? entry.host ?? "–").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Image(systemName: entry.allowed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(entry.allowed ? .green : .red)
                }
                Text(entry.path ?? "/").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    Text([entry.actor, entry.ip, entry.location].compactMap { $0 }.joined(separator: " · "))
                    Spacer()
                    Text(Format.dateTime(entry.timestamp))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AccessLogRow: View {
    let entry: AccessLogEntry

    var body: some View {
        GlassCard(tint: entry.allowed ? nil : Color.red, padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.type ?? "Zugriff").font(.caption.monospaced().bold())
                    Text(entry.resourceName ?? "–").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Image(systemName: entry.allowed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(entry.allowed ? .green : .red)
                }
                HStack {
                    Text([entry.actor, entry.ip, entry.location].compactMap { $0 }.joined(separator: " · "))
                    Spacer()
                    Text(Format.dateTime(entry.timestamp))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ActionLogRow: View {
    let entry: ActionLogEntry

    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.action).font(.subheadline.monospaced().weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text(Format.dateTime(entry.timestamp)).font(.caption2).foregroundStyle(.secondary)
                }
                Text([entry.actor, entry.actorType].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let metadata = entry.metadata, !metadata.isEmpty {
                    Text(metadata)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
    }
}
