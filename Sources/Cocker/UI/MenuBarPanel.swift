import SwiftUI

/// Le panneau déroulant de la barre de menus : tout le quotidien tient ici.
struct MenuBarPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.locale) private var locale

    @State private var collapsedGroups: Set<String> = []

    /// Le panneau garde toujours la même taille.
    ///
    /// La fenêtre d'un `MenuBarExtra` grandit avec son contenu mais ne
    /// rétrécit pas : une liste qui se vide laissait un grand trou transparent
    /// au-dessus du panneau. Une hauteur constante supprime le problème à la
    /// racine, et donne au passage un panneau qui ne saute pas sous la souris
    /// quand un conteneur apparaît.
    static let panelSize = CGSize(width: 380, height: 540)

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
                .frame(maxHeight: .infinity)

            Divider()

            footer
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .onAppear { state.isPanelVisible = true }
        .onDisappear { state.isPanelVisible = false }
    }

    // MARK: - En-tête

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Cocker")
                    .font(.headline)

                StatusPill(
                    text: state.vm.state.label,
                    color: state.vm.state.color,
                    isPulsing: state.vm.state.isBusy
                )

                Spacer()

                powerButton
            }

            if state.vm.state.isUsable {
                HStack(spacing: 14) {
                    MetricTile(
                        value: String(state.vm.resources.cpus),
                        unit: "cores",
                        label: "Processor",
                        systemImage: "cpu"
                    )
                    MetricTile(
                        value: formatted(state.vm.resources.memoryGiB),
                        unit: "GiB",
                        label: "Memory",
                        systemImage: "memorychip"
                    )
                    MetricTile(
                        value: diskValue,
                        unit: diskUnit,
                        label: "Disk",
                        systemImage: "internaldrive"
                    )
                }
            }

            if let operation = state.runningOperation {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(verbatim: String(
                        format: localized(operation.key, locale),
                        operation.argument ?? ""
                    ))
                    .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if let error = state.lastError {
                ErrorBanner(message: error) { state.dismissError() }
            }
        }
        .padding(12)
    }

    private var powerButton: some View {
        Button {
            Task { await state.toggleVM() }
        } label: {
            Image(systemName: state.vm.state.isUsable ? "stop.circle.fill" : "play.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(state.vm.state.isUsable ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(state.isBusy || state.needsOnboarding)
        .help(state.vm.state.isUsable ? "Back to the basket" : "Wake Cocker up")
    }

    // MARK: - Corps

    @ViewBuilder
    private var content: some View {
        if state.needsOnboarding {
            EmptyStateView(
                systemImage: "shippingbox",
                title: DogTalk.Label.notTrained,
                message: onboardingMessage,
                actionTitle: "Train him"
            ) {
                open(WindowID.onboarding)
            }
        } else if !state.vm.state.isUsable {
            EmptyStateView(
                systemImage: "moon.zzz",
                title: DogTalk.Label.idle,
                message: "Wake him up to see your containers again.",
                actionTitle: state.isBusy ? nil : "Wake Cocker up"
            ) {
                Task { await state.startVM() }
            }
        } else if visibleGroups.isEmpty {
            EmptyStateView(
                systemImage: "tray",
                title: DogTalk.Label.emptyKennel,
                message: state.preferences.showStoppedContainers
                    ? "Start a stack with `docker compose up` and Cocker will watch it here."
                    : "Nothing running. Stopped containers are hidden."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 4, pinnedViews: .sectionHeaders) {
                    ForEach(visibleGroups) { group in
                        groupSection(group)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            }
        }
    }

    private var onboardingMessage: String {
        let missing = state.missingRequiredTools.map(\.kind.displayName)
        if missing.isEmpty {
            return localized("Only the Docker virtual machine is left to create.", locale)
        }
        return String(format: localized("Missing: %@", locale), missing.joined(separator: ", "))
    }

    /// Les groupes filtrés selon la préférence « afficher les conteneurs arrêtés ».
    private var visibleGroups: [ContainerGroup] {
        guard !state.preferences.showStoppedContainers else { return state.groups }
        return state.groups.compactMap { group in
            let running = group.containers.filter { $0.state.isRunning }
            guard !running.isEmpty else { return nil }
            return ContainerGroup(name: group.name, containers: running)
        }
    }

    @ViewBuilder
    private func groupSection(_ group: ContainerGroup) -> some View {
        let isCollapsed = collapsedGroups.contains(group.name)

        Section {
            if !isCollapsed {
                ForEach(group.containers) { container in
                    ContainerRow(container: container)
                }
            }
        } header: {
            GroupHeader(
                group: group,
                isCollapsed: isCollapsed,
                onToggleCollapse: {
                    if isCollapsed {
                        collapsedGroups.remove(group.name)
                    } else {
                        collapsedGroups.insert(group.name)
                    }
                }
            )
        }
    }

    // MARK: - Pied

    private var footer: some View {
        HStack(spacing: 12) {
            if state.vm.state.isUsable {
                Text("\(state.runningContainerCount) on watch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .help("Resources, startup, housekeeping")

            Menu {
                Button("Setup assistant…") { open(WindowID.onboarding) }
                Button("Refresh now") { Task { await state.refresh() } }
                Divider()
                Button("About Cocker") { open(WindowID.about) }
                Button("Quit Cocker") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Utilitaires

    /// Une app sans icône dans le Dock ne passe pas au premier plan toute
    /// seule : il faut l'activer pour que la fenêtre s'affiche devant.
    private func open(_ id: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private var diskValue: String {
        guard let usage = state.diskUsage else { return String(state.vm.resources.diskGiB) }
        let usedGiB = Double(usage.totalBytes) / 1_073_741_824
        return String(format: "%.1f", usedGiB)
    }

    private var diskUnit: LocalizedStringKey {
        state.diskUsage == nil
            ? LocalizedStringKey("GiB allocated")
            : LocalizedStringKey("GiB / \(state.vm.resources.diskGiB)")
    }
}

// MARK: - En-tête de projet

private struct GroupHeader: View {
    @Environment(AppState.self) private var state

    var group: ContainerGroup
    var isCollapsed: Bool
    var onToggleCollapse: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggleCollapse) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            Image(systemName: group.isLoose ? "shippingbox" : "square.stack.3d.up")
                .font(.caption)
                .foregroundStyle(group.isRunning ? Color.accentColor : Color.secondary)

            Text(key: group.displayName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Text(verbatim: "\(group.runningCount)/\(group.containers.count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            // Un projet Compose se pilote en bloc ; un conteneur isolé non.
            if !group.isLoose {
                Button {
                    Task { await state.perform(group.isRunning ? .stop : .start, on: group) }
                } label: {
                    // Les variantes cerclées plutôt que pleines : à cette
                    // taille, un `stop.fill` n'est qu'un carré, qu'on prend
                    // pour une case à cocher.
                    Image(systemName: group.isRunning ? "stop.circle" : "play.circle")
                        .font(.body)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(state.isBusy)
                .help(group.isRunning ? "Stop the project" : "Start the project")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Ligne de conteneur

private struct ContainerRow: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale

    var container: Container
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: container.state.color, isPulsing: container.state == .restarting)

            VStack(alignment: .leading, spacing: 1) {
                Text(container.displayName)
                    .font(.callout)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isHovered {
                actions
            } else {
                ports
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(isHovered ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { isHovered = $0 }
    }

    /// Composé, donc résolu à la main : `Text` ne traduit que des littéraux.
    /// `status` vient de docker et reste tel quel, c'est sa sortie brute.
    private var subtitle: String {
        let status = container.status.isEmpty
            ? localized(container.state.label, locale)
            : container.status
        return "\(container.image) · \(status)"
    }

    /// Les ports publiés sont cliquables : c'est le geste le plus fréquent.
    @ViewBuilder
    private var ports: some View {
        if !container.ports.isEmpty {
            HStack(spacing: 4) {
                ForEach(container.ports.prefix(2)) { port in
                    Button {
                        if let url = port.localURL { NSWorkspace.shared.open(url) }
                    } label: {
                        Text(String(port.hostPort))
                            .font(.system(size: 10, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!container.state.isRunning || !port.isWebLikely)
                    .help("Open http://localhost:\(port.hostPort)")
                }
                if container.ports.count > 2 {
                    Text(verbatim: "+\(container.ports.count - 2)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button {
                Task { await state.perform(container.state.isRunning ? .stop : .start, on: container) }
            } label: {
                Image(systemName: container.state.isRunning ? "stop.fill" : "play.fill")
            }
            .help(container.state.isRunning ? "Stop" : "Start")

            Button {
                Task { await state.perform(.restart, on: container) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(!container.state.isRunning)
            .help("Restart")

            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: WindowID.logs, value: container.id)
            } label: {
                Image(systemName: "text.alignleft")
            }
            .help("View logs")
        }
        .font(.caption)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(state.isBusy)
    }
}

