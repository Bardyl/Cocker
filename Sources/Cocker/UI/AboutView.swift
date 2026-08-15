import SwiftUI

/// La fenêtre « À propos ».
///
/// En anglais, contrairement au reste de l'interface : elle porte la licence,
/// la mention de marque et les crédits, qui s'adressent à quiconque récupère
/// le dépôt, pas seulement aux francophones.
struct AboutView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            identity
            Divider()
            legal
        }
        .frame(width: 460)
        .background(.background)
    }

    private var identity: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)

            VStack(spacing: 3) {
                Text("Cocker")
                    .font(.largeTitle.weight(.semibold))
                Text("A menu bar Docker environment for macOS, without Docker Desktop.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Version \(Updater.currentVersion) (\(buildNumber))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .padding(.top, 2)
            }

            UpdateStatusView()

            HStack(spacing: 10) {
                Link("Source code", destination: URL(string: "https://github.com/\(Updater.repository)")!)
                Text("·").foregroundStyle(.tertiary)
                Link("Report an issue", destination: URL(string: "https://github.com/\(Updater.repository)/issues")!)
                Text("·").foregroundStyle(.tertiary)
                Link("Releases", destination: Updater.releasesURL)
            }
            .font(.callout)
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 20)
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Released under the MIT License. Copyright © 2026 Mathieu Menut.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Cocker drives Homebrew, colima and the Docker CLI as separate programs. "
                 + "It does not bundle them; each keeps its own license.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Le nom joue avec celui de Docker : autant être explicite plutôt
            // que de laisser planer un doute sur une éventuelle affiliation.
            Text("Not affiliated with, endorsed by, or sponsored by Docker, Inc. "
                 + "Docker and the Docker logo are trademarks of Docker, Inc.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

/// L'état de la vérification de mise à jour, avec son bouton.
private struct UpdateStatusView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 8) {
            switch state.updater.state {
            case .idle:
                checkButton

            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking…")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .upToDate:
                Label("You're up to date", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                checkButton

            case .available(let version, let url):
                Link(destination: url) {
                    Label("Version \(version) is available", systemImage: "arrow.down.circle.fill")
                        .font(.caption.weight(.medium))
                }

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                checkButton
            }
        }
        .frame(height: 22)
    }

    private var checkButton: some View {
        Button("Check for updates") {
            Task { await state.updater.check() }
        }
        .controlSize(.small)
    }
}
