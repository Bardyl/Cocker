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
                .tabItem { Label("Resources", systemImage: "gauge.with.dots.needle.50percent") }

            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }

            MaintenanceTab()
                .tabItem { Label("Housekeeping", systemImage: "sparkles") }
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
                Text("What the virtual machine takes from your Mac")
            } footer: {
                Text(ResourceControls.diskCaveat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("x86 emulation through Rosetta", isOn: $preferences.useRosetta)
            } footer: {
                Text("Speeds up amd64 images considerably on Apple Silicon.")
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

    private var appliedSummary: LocalizedStringKey {
        switch state.vm.state {
        case .missing, .notCreated:
            "The VM does not exist yet: these values will be used to create it."
        default:
            "These settings match the running VM."
        }
    }

    /// Changer les ressources impose un cycle stop/start : les conteneurs
    /// tombent. L'utilisateur doit le savoir avant de cliquer.
    private var pendingChange: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "Applying restarts the VM: running containers will stop.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.callout)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Discard the changes") {
                    state.preferences.adopt(state.vm.resources)
                }
                .disabled(state.isBusy)

                Spacer()

                if state.isBusy { ProgressView().controlSize(.small) }

                Button("Apply and restart") {
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
                Toggle("Start Docker when Cocker launches", isOn: $preferences.startVMAtLaunch)
            } header: {
                Text("Startup")
            } footer: {
                Text(
                    "The colima VM keeps running after you quit Cocker: `docker` stays usable in your terminal."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Picker("Language", selection: $preferences.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(key: language.label).tag(language)
                    }
                }
            } header: {
                Text("Display")
            } footer: {
                Text("The change applies straight away, no restart needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show stopped containers", isOn: $preferences.showStoppedContainers)
            }

            Section {
                Toggle("Check for updates at launch", isOn: $preferences.checksForUpdates)
            } footer: {
                Text(
                    "One request a day to the GitHub API, and nothing else: Cocker makes no other network call."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Virtual machine") {
                InfoRow(label: "State", value: state.vm.state.label)
                InfoRow(label: "Architecture", value: state.vm.architecture ?? "—")
                InfoRow(label: "Engine", value: state.vm.runtime ?? "—")
                InfoRow(label: "Docker socket", value: shortSocketPath)
            }

            Section {
                Button("Reopen the setup assistant…") {
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
        return
            raw
            .replacingOccurrences(of: "unix://", with: "")
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

private struct InfoRow: View {
    var label: LocalizedStringKey
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
            Section("Space used") {
                if let usage = state.diskUsage {
                    UsageRow(label: "Images", bytes: usage.imagesBytes)
                    UsageRow(label: "Containers", bytes: usage.containersBytes)
                    UsageRow(label: "Volumes", bytes: usage.volumesBytes)
                    UsageRow(
                        label: "Reclaimable", bytes: usage.reclaimableBytes, isHighlighted: true)
                } else {
                    Text(
                        state.vm.state.isUsable
                            ? "Working it out…"
                            : "Start Docker to find out how much space is used."
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Also delete unused volumes", isOn: $pruneVolumes)

                HStack {
                    Button("Clean up…") { isConfirmingPrune = true }
                        .disabled(state.isBusy || !state.vm.state.isUsable)

                    if state.isBusy { ProgressView().controlSize(.small) }

                    Spacer()

                    Button("Refresh") {
                        Task {
                            await state.refresh()
                            await state.refreshDiskUsage()
                        }
                    }
                    .disabled(state.isBusy)
                }
            } header: {
                Text("Cleaning")
            } footer: {
                Text(
                    pruneVolumes
                        ? "Volumes hold your development databases. Anything not attached to a container will be lost."
                        : "Deletes stopped containers, orphaned networks and unused images."
                )
                .font(.caption)
                .foregroundStyle(pruneVolumes ? Color.orange : Color.secondary)
            }

            Section("Log") {
                LogConsole(lines: state.log, emptyMessage: "No recent operation.")
                    .frame(height: 110)
            }
        }
        .formStyle(.grouped)
        .task { await state.refreshDiskUsage() }
        .confirmationDialog("Clean up Docker?", isPresented: $isConfirmingPrune) {
            Button("Clean up", role: .destructive) {
                Task { await state.prune(includeVolumes: pruneVolumes) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                pruneVolumes
                    ? "Unused images, stopped containers, networks and volumes will be deleted. This cannot be undone."
                    : "Unused images, stopped containers and networks will be deleted.")
        }
    }
}

private struct UsageRow: View {
    var label: LocalizedStringKey
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
