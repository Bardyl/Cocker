import SwiftUI

/// Pastille colorée qui résume un état d'un coup d'œil.
struct StatusDot: View {
    var color: Color
    var isPulsing: Bool = false

    @State private var isDim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(isPulsing && isDim ? 0.25 : 1)
            .animation(
                isPulsing ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default,
                value: isDim
            )
            .onAppear { if isPulsing { isDim = true } }
    }
}

/// Étiquette compacte « pastille + texte » utilisée dans les en-têtes.
struct StatusPill: View {
    var text: String
    var color: Color
    var isPulsing: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(color: color, isPulsing: isPulsing)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// Une mesure : valeur en gras, unité et libellé discrets.
struct MetricTile: View {
    var value: String
    var unit: String?
    var label: String
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .labelStyle(.titleAndIcon)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Bandeau d'erreur refermable.
struct ErrorBanner: View {
    var message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// État vide : une icône, une phrase, éventuellement une action.
struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.callout.weight(.medium))

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}

/// Journal défilant, réutilisé par l'assistant et par la vue des logs.
struct LogConsole: View {
    var lines: [AppState.LogLine]
    var emptyMessage: String = "Rien à afficher pour l'instant."

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if lines.isEmpty {
                        Text(emptyMessage)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(8)
                    }
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(line.isError ? Color.red : .secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onChange(of: lines.count) {
                // Un journal qui ne suit pas la dernière ligne ne sert à rien.
                guard let last = lines.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

extension VMState {
    var color: Color {
        switch self {
        case .running: .green
        case .starting, .stopping: .orange
        case .stopped, .notCreated: .secondary
        case .missing: .red
        case .unknown: .secondary
        }
    }
}

extension Container.State {
    var color: Color {
        switch self {
        case .running: .green
        case .restarting, .created: .orange
        case .paused: .yellow
        case .exited, .dead, .removing: .secondary
        case .unknown: .secondary
        }
    }
}
