import SwiftUI

/// La fenêtre de réglages.
///
/// Chaque onglet est un `Form` groupé : c'est ce qui donne les blocs, les
/// libellés alignés et les légendes sous les sections, comme dans les Réglages
/// Système. Sans lui, le contenu flotte et laisse un grand vide au milieu.
struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TabView {
            ResourcesTab()
                .tabItem { Label("Ressources", systemImage: "gauge.with.dots.needle.50percent") }

            GeneralTab()
                .tabItem { Label("Général", systemImage: "gearshape") }

            MaintenanceTab()
                .tabItem { Label("Entretien", systemImage: "sparkles") }
        }
        .frame(width: 520, height: 460)
        .environment(state)
    }
}

// MARK: - Ressources

private struct ResourcesTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var preferences = state.preferences

        Form {
            Section {
                ResourceControls(resources: $preferences.desiredResources)
            } header: {
                Text("Ce que la machine virtuelle prend à ton Mac")
            } footer: {
                Text(ResourceControls.diskCaveat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Émulation x86 par Rosetta", isOn: $preferences.useRosetta)
            } footer: {
                Text("Accélère nettement les images amd64 sur Apple Silicon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if state.hasPendingResourceChange {
                    pendingChange
                } else {
                    Text(appliedSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var appliedSummary: String {
        switch state.vm.state {
        case .missing, .notCreated:
            "La VM n'existe pas encore : ces valeurs serviront à sa création."
        default:
            "Ces réglages sont ceux de la VM en cours."
        }
    }

    /// Changer les ressources impose un cycle stop/start : les conteneurs
    /// tombent. L'utilisateur doit le savoir avant de cliquer.
    private var pendingChange: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "Appliquer redémarre la VM : les conteneurs en marche s'arrêteront.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.callout)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Annuler les changements") {
                    state.preferences.adopt(state.vm.resources)
                }
                .disabled(state.isBusy)

                Spacer()

                if state.isBusy { ProgressView().controlSize(.small) }

                Button("Appliquer et redémarrer") {
                    Task { await state.applyResources() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isBusy)
            }
        }
    }
}

// MARK: - Général

private struct GeneralTab: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var preferences = state.preferences

        Form {
            Section {
                LoginItemToggle()
                Toggle("Démarrer Docker à l'ouverture de Cocker", isOn: $preferences.startVMAtLaunch)
            } header: {
                Text("Démarrage")
            } footer: {
                Text("La VM colima continue de tourner après avoir quitté Cocker : "
                     + "`docker` reste utilisable dans le terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Affichage") {
                Toggle("Afficher les conteneurs arrêtés", isOn: $preferences.showStoppedContainers)
            }

            Section {
                Toggle("Vérifier les mises à jour au lancement", isOn: $preferences.checksForUpdates)
            } footer: {
                Text("Une requête par jour vers l'API GitHub, et rien d'autre : "
                     + "Cocker n'émet aucun autre appel réseau.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Machine virtuelle") {
                InfoRow(label: "État", value: state.vm.state.label)
                InfoRow(label: "Architecture", value: state.vm.architecture ?? "—")
                InfoRow(label: "Moteur", value: state.vm.runtime ?? "—")
                InfoRow(label: "Socket Docker", value: shortSocketPath)
            }

            Section {
                Button("Rouvrir l'assistant de configuration…") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: WindowID.onboarding)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Le chemin complet déborde de sa ligne : `~` suffit à le rendre lisible.
    private var shortSocketPath: String {
        let raw = state.vm.dockerSocket ?? Colima.dockerSocketPath()
        return raw
            .replacingOccurrences(of: "unix://", with: "")
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

private struct InfoRow: View {
    var label: String
    var value: String

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Entretien

private struct MaintenanceTab: View {
    @Environment(AppState.self) private var state

    @State private var isConfirmingPrune = false
    @State private var pruneVolumes = false

    var body: some View {
        Form {
            Section("Espace occupé") {
                if let usage = state.diskUsage {
                    UsageRow(label: "Images", bytes: usage.imagesBytes)
                    UsageRow(label: "Conteneurs", bytes: usage.containersBytes)
                    UsageRow(label: "Volumes", bytes: usage.volumesBytes)
                    UsageRow(label: "Récupérable", bytes: usage.reclaimableBytes, isHighlighted: true)
                } else {
                    Text(state.vm.state.isUsable
                         ? "Calcul en cours…"
                         : "Démarre Docker pour connaître l'espace occupé.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Supprimer aussi les volumes inutilisés", isOn: $pruneVolumes)

                HStack {
                    Button("Nettoyer…") { isConfirmingPrune = true }
                        .disabled(state.isBusy || !state.vm.state.isUsable)

                    if state.isBusy { ProgressView().controlSize(.small) }

                    Spacer()

                    Button("Rafraîchir") {
                        Task {
                            await state.refresh()
                            await state.refreshDiskUsage()
                        }
                    }
                    .disabled(state.isBusy)
                }
            } header: {
                Text("Nettoyage")
            } footer: {
                Text(pruneVolumes
                     ? "Les volumes contiennent tes bases de données de développement. "
                       + "Ce qui n'est rattaché à aucun conteneur sera perdu."
                     : "Supprime les conteneurs arrêtés, les réseaux orphelins et les "
                       + "images inutilisées.")
                    .font(.caption)
                    .foregroundStyle(pruneVolumes ? Color.orange : Color.secondary)
            }

            Section("Journal") {
                LogConsole(lines: state.log, emptyMessage: "Aucune opération récente.")
                    .frame(height: 110)
            }
        }
        .formStyle(.grouped)
        .task { await state.refreshDiskUsage() }
        .confirmationDialog("Nettoyer Docker ?", isPresented: $isConfirmingPrune) {
            Button("Nettoyer", role: .destructive) {
                Task { await state.prune(includeVolumes: pruneVolumes) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(pruneVolumes
                 ? "Les images, conteneurs arrêtés, réseaux et volumes inutilisés seront supprimés. C'est irréversible."
                 : "Les images, conteneurs arrêtés et réseaux inutilisés seront supprimés.")
        }
    }
}

private struct UsageRow: View {
    var label: String
    var bytes: Int64
    var isHighlighted: Bool = false

    var body: some View {
        LabeledContent(label) {
            Text(ByteSize.format(bytes))
                .monospacedDigit()
                .foregroundStyle(isHighlighted ? Color.accentColor : .primary)
        }
        .foregroundStyle(isHighlighted ? .primary : .secondary)
    }
}
