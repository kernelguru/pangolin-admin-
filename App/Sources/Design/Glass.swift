import SwiftUI

// Liquid Glass building blocks (iOS 26).
// Content sits on a soft, slowly moving mesh gradient; cards and controls use `glassEffect`.

/// Full-screen animated background behind every screen.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let drift = Float(sin(t / 6) * 0.08)
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.5 + drift, 0.5 - drift], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1]
                ],
                colors: palette
            )
        }
        .ignoresSafeArea()
    }

    private var palette: [Color] {
        if colorScheme == .dark {
            [
                Color(red: 0.05, green: 0.07, blue: 0.16), Color(red: 0.10, green: 0.10, blue: 0.28), Color(red: 0.04, green: 0.16, blue: 0.22),
                Color(red: 0.12, green: 0.07, blue: 0.24), Color(red: 0.05, green: 0.20, blue: 0.30), Color(red: 0.03, green: 0.10, blue: 0.18),
                Color(red: 0.02, green: 0.05, blue: 0.12), Color(red: 0.10, green: 0.05, blue: 0.20), Color(red: 0.03, green: 0.12, blue: 0.14)
            ]
        } else {
            [
                Color(red: 0.84, green: 0.90, blue: 1.00), Color(red: 0.90, green: 0.86, blue: 1.00), Color(red: 0.80, green: 0.95, blue: 0.97),
                Color(red: 0.93, green: 0.88, blue: 0.99), Color(red: 0.78, green: 0.90, blue: 0.99), Color(red: 0.86, green: 0.97, blue: 0.94),
                Color(red: 0.95, green: 0.93, blue: 1.00), Color(red: 0.84, green: 0.88, blue: 0.99), Color(red: 0.88, green: 0.96, blue: 0.98)
            ]
        }
    }
}

/// A rounded glass panel.
struct GlassCard<Content: View>: View {
    var tint: Color?
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    private var glass: Glass {
        if let tint { return .regular.tint(tint.opacity(0.25)) }
        return .regular
    }
}

/// Section title above a group of cards.
struct GlassSectionHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Scrollable screen layout: background + vertical stack of cards.
struct GlassScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
    }
}

/// Small coloured dot + text.
struct StatusPill: View {
    let text: String
    let color: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            } else {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .glassEffect(.regular.tint(color.opacity(0.3)), in: .capsule)
    }
}

/// Key/value row used in detail screens.
struct InfoRow: View {
    let label: String
    let value: String?
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value?.isEmpty == false ? value! : "–")
                .multilineTextAlignment(.trailing)
                .font(monospaced ? .callout.monospaced() : .callout)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

/// Large number tile for the dashboard.
struct MetricTile: View {
    let title: String
    let value: String
    var detail: String?
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        GlassCard(tint: tint, cornerRadius: 22, padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Placeholder for empty lists and errors.
struct GlassMessage: View {
    let title: String
    var message: String?
    var systemImage: String
    var retry: (() -> Void)?

    var body: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(title).font(.headline)
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let retry {
                    Button("Erneut versuchen", action: retry)
                        .buttonStyle(.glass)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }
}
