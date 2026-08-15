import SwiftUI

/// Les logs d'un conteneur, dans leur propre fenêtre.
///
/// Une feuille modale sur le panneau de la barre de menus disparaîtrait au
/// premier clic ailleurs : une vraie fenêtre est le bon support pour du texte
/// qu'on lit longtemps.
struct LogsView: View {
    @Environment(AppState.self) private var state

    var containerID: String?

    @State private var text = ""
    @State private var isLoading = false
    @State private var autoRefresh = true

    private var container: Container? {
        guard let containerID else { return nil }
        return state.allContainers.first { $0.id == containerID }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            console
        }
        .frame(minWidth: 560, minHeight: 360)
        .task(id: containerID) { await load() }
        .task(id: autoRefresh) {
            // Un suivi paresseux plutôt qu'un `docker logs -f` : ça évite de
            // garder un processus vivant par fenêtre ouverte.
            while autoRefresh, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard autoRefresh else { break }
                await load(silently: true)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if let container {
                StatusDot(color: container.state.color)
                VStack(alignment: .leading, spacing: 0) {
                    Text(container.displayName).font(.headline)
                    Text(container.project ?? container.image)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Container not found").font(.headline)
            }

            Spacer()

            if isLoading { ProgressView().controlSize(.small) }

            Toggle("Follow", isOn: $autoRefresh)
                .toggleStyle(.switch)
                .controlSize(.mini)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy the logs")
            .disabled(text.isEmpty)
        }
        .padding(12)
    }

    private var console: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? String(localized: "No output.") : text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .id("bottom")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: text) {
                guard autoRefresh else { return }
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func load(silently: Bool = false) async {
        guard let container else { return }
        if !silently { isLoading = true }
        let output = await state.logs(for: container)
        text = output
        isLoading = false
    }
}
