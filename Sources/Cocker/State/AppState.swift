import Foundation
import Observation
import SwiftUI

/// Le cerveau de l'app : sonde l'environnement, garde l'état courant et
/// exécute les actions demandées par l'interface.
@MainActor
@Observable
final class AppState {

    // MARK: - État observable

    private(set) var tools: [Tool] = []
    private(set) var vm: VMStatus = .unknown
    private(set) var groups: [ContainerGroup] = []
    private(set) var diskUsage: DiskUsage?

    /// Opération longue en cours (démarrage, installation…). Non nil = l'UI
    /// verrouille les boutons qui pourraient entrer en conflit.
    ///
    /// On garde la clé de traduction et son argument plutôt que le texte
    /// final : la langue peut changer pendant l'opération.
    struct Operation: Equatable, Sendable {
        var key: String
        var argument: String?

        init(_ key: String, _ argument: String? = nil) {
            self.key = key
            self.argument = argument
        }
    }

    private(set) var runningOperation: Operation?
    private(set) var lastError: String?
    private(set) var log: [LogLine] = []

    /// Le panneau de la barre de menus est-il ouvert ? Rafraîchir vite ne sert
    /// à rien quand personne ne regarde.
    var isPanelVisible = false {
        didSet { if isPanelVisible { Task { await refresh() } } }
    }

    let preferences: Preferences
    let updater = Updater()

    // MARK: - Dérivés

    var missingRequiredTools: [Tool] {
        tools.filter { $0.kind.isRequired && !$0.isInstalled }
    }

    var missingOptionalTools: [Tool] {
        tools.filter { !$0.kind.isRequired && !$0.isInstalled }
    }

    /// Installés mais invisibles du CLI docker : un lien les répare.
    var unlinkedTools: [Tool] {
        tools.filter(\.needsLinking)
    }

    /// Y a-t-il quelque chose à installer ou à réparer ?
    var hasToolWork: Bool {
        !missingRequiredTools.isEmpty || !missingOptionalTools.isEmpty || !unlinkedTools.isEmpty
    }

    /// L'onboarding s'impose tant que l'essentiel manque, ou que la VM n'a
    /// jamais été créée.
    var needsOnboarding: Bool {
        !missingRequiredTools.isEmpty || vm.state == .missing || vm.state == .notCreated
    }

    var allContainers: [Container] {
        groups.flatMap(\.containers)
    }

    var runningContainerCount: Int {
        allContainers.filter { $0.state.isRunning }.count
    }

    /// Les réglages diffèrent-ils de ce que la VM applique réellement ?
    var hasPendingResourceChange: Bool {
        vm.state != .missing && vm.state != .notCreated && vm.resources != preferences.desiredResources
    }

    var isBusy: Bool { runningOperation != nil }

    // MARK: - Cycle de vie

    private var pollingTask: Task<Void, Never>?

    init(preferences: Preferences = Preferences()) {
        self.preferences = preferences
    }

    /// Premier sondage, puis boucle de rafraîchissement.
    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()

                // La décision ne se prend qu'au premier tour : sinon, arrêter
                // Docker depuis le panneau le verrait redémarrer aussitôt.
                if !self.hasAttemptedAutoStart {
                    let shouldStart = self.preferences.startVMAtLaunch && self.canAutoStartVM
                    self.hasAttemptedAutoStart = true
                    if shouldStart { await self.startVM() }
                }

                await self.updater.checkQuietlyIfDue(
                    enabled: self.preferences.checksForUpdates
                )

                // Panneau ouvert : on veut voir les conteneurs bouger.
                // Panneau fermé : seul le compteur de l'icône compte.
                let interval: Duration = self.isPanelVisible ? .seconds(3) : .seconds(15)
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Vrai dès que la question « faut-il démarrer la VM ? » a été tranchée,
    /// que la réponse ait été oui ou non.
    private var hasAttemptedAutoStart = false

    private var canAutoStartVM: Bool {
        !isBusy && vm.state == .stopped && !needsOnboarding
    }

    // MARK: - Sondage

    /// Sonder les outils coûte cinq processus, dont `brew --version` qui est
    /// lent : inutile de le refaire à chaque tour de boucle. Le disque ne
    /// change qu'après une installation, et celles-ci forcent le sondage.
    private var lastToolProbe: Date?
    private static let toolProbeInterval: TimeInterval = 60

    func refreshTools() async {
        tools = await Toolchain.probe()
        lastToolProbe = Date()
    }

    func refresh() async {
        let isStale = lastToolProbe.map { Date().timeIntervalSince($0) > Self.toolProbeInterval } ?? true
        if isStale { await refreshTools() }

        vm = await Colima.status()

        // Une VM à l'arrêt n'a pas de démon à interroger.
        guard vm.state.isUsable else {
            // Pendant un démarrage ou un arrêt, on garde la dernière liste
            // connue : la vider ferait s'effondrer le panneau d'un coup, et
            // l'utilisateur préfère voir ce qui est en train de s'éteindre.
            if !vm.state.isBusy {
                groups = []
                diskUsage = nil
            }
            // Une erreur docker n'a plus de sens sans démon en face : la
            // laisser affichée ferait passer un arrêt volontaire pour une panne.
            lastError = nil
            return
        }

        // colima annonce la VM debout quelques secondes avant que le démon
        // docker écoute. L'interroger maintenant ne renseignerait sur rien.
        guard Docker.isSocketAvailable else {
            lastError = nil
            return
        }

        do {
            groups = Docker.group(try await Docker.containers())
            lastError = nil
        } catch {
            groups = []
            // Un démon injoignable pendant une manœuvre, ce n'est pas une
            // panne : c'est la course entre le sondage et la VM. Le reste,
            // en revanche, mérite d'être montré tel quel.
            let isTransient = vm.state.isBusy
                || runningOperation != nil
                || Docker.isDaemonUnreachable(error.localizedDescription)
            lastError = isTransient ? nil : error.localizedDescription
        }

        // Le calcul d'espace disque est lent : seulement quand on regarde.
        if isPanelVisible {
            await refreshDiskUsage()
        }
    }

    /// `docker system df` à la demande — l'onglet Entretien en dépend, et il
    /// s'ouvre sans que le panneau le soit.
    func refreshDiskUsage() async {
        guard vm.state.isUsable else {
            diskUsage = nil
            return
        }
        diskUsage = try? await Docker.diskUsage()
    }

    // MARK: - Journal

    struct LogLine: Identifiable, Sendable {
        let id = UUID()
        var text: String
        var isError: Bool = false
    }

    func appendLog(_ text: String, isError: Bool = false) {
        log.append(LogLine(text: text, isError: isError))
        // Une installation Homebrew crache des milliers de lignes : on garde
        // la fin, c'est là que se trouve l'erreur éventuelle.
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }

    func clearLog() { log.removeAll() }

    // MARK: - Actions

    /// Enveloppe commune : marque l'opération, capture l'erreur, rafraîchit.
    private func perform(_ operation: Operation, _ body: () async throws -> Void) async {
        guard runningOperation == nil else { return }
        runningOperation = operation
        lastError = nil
        defer { runningOperation = nil }

        do {
            try await body()
        } catch {
            lastError = error.localizedDescription
            appendLog(error.localizedDescription, isError: true)
        }

        // Une opération vient peut-être d'installer ou de lier un outil :
        // le cache du sondage n'est plus fiable.
        lastToolProbe = nil
        await refresh()
    }

    /// Collecte les lignes d'un processus depuis n'importe quel thread.
    private nonisolated func logCollector() -> @Sendable (String) -> Void {
        { [weak self] line in
            Task { @MainActor [weak self] in self?.appendLog(line) }
        }
    }

    func startVM() async {
        await perform(Operation(DogTalk.Operation.start)) {
            vm.state = .starting
            try await Colima.start(
                resources: preferences.desiredResources,
                useRosetta: preferences.useRosetta,
                onOutput: logCollector()
            )
        }
    }

    func stopVM() async {
        await perform(Operation(DogTalk.Operation.stop)) {
            vm.state = .stopping
            try await Colima.stop(onOutput: logCollector())
        }
    }

    func toggleVM() async {
        switch vm.state {
        case .running: await stopVM()
        case .stopped, .notCreated: await startVM()
        default: break
        }
    }

    /// Applique de nouvelles ressources : colima exige un cycle complet.
    func applyResources() async {
        await perform(Operation(DogTalk.Operation.resize)) {
            appendLog("Restarting the VM to apply the new resources.")
            try await Colima.restart(
                resources: preferences.desiredResources,
                useRosetta: preferences.useRosetta,
                onOutput: logCollector()
            )
        }
    }

    func install(_ kind: Tool.Kind) async {
        await perform(Operation(DogTalk.Operation.installOne, kind.displayName)) {
            try await Toolchain.install(kind, onOutput: logCollector())
        }
    }

    func link(_ kind: Tool.Kind) async {
        await perform(Operation(DogTalk.Operation.linkOne, kind.displayName)) {
            try Toolchain.linkPlugin(kind, onOutput: logCollector())
        }
    }

    /// Installe tout ce qui manque et répare ce qui est mal branché.
    func installAllMissing() async {
        let toInstall = (missingRequiredTools + missingOptionalTools)
            .map(\.kind)
            .filter { $0.formula != nil }
        let toLink = unlinkedTools.map(\.kind)

        await perform(Operation(DogTalk.Operation.installAll)) {
            for kind in toInstall {
                try await Toolchain.install(kind, onOutput: logCollector())
            }
            for kind in toLink {
                try Toolchain.linkPlugin(kind, onOutput: logCollector())
            }
        }
    }

    func perform(_ action: Docker.Action, on container: Container) async {
        await perform(Operation(action.label + " %@", container.displayName)) {
            try await Docker.perform(action, on: container.id)
        }
    }

    func perform(_ action: Docker.Action, on group: ContainerGroup) async {
        await perform(Operation(action.label + " %@", group.displayName)) {
            try await Docker.perform(action, on: group)
        }
    }

    func logs(for container: Container) async -> String {
        do {
            return try await Docker.logs(for: container.id)
        } catch {
            return error.localizedDescription
        }
    }

    func prune(includeVolumes: Bool) async {
        await perform(Operation(DogTalk.Operation.cleaning)) {
            try await Docker.prune(includeVolumes: includeVolumes, onOutput: logCollector())
        }
    }

    func dismissError() { lastError = nil }
}
