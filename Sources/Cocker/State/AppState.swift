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
        vm.state != .missing && vm.state != .notCreated
            && vm.resources != preferences.desiredResources
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

                try? await Task.sleep(for: self.pollingInterval)
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

    /// Trois rythmes, selon ce qu'il y a à voir.
    ///
    /// Panneau ouvert, on regarde les conteneurs bouger. Panneau fermé mais VM
    /// en marche, seul le compteur de l'icône dépend du sondage. VM à l'arrêt,
    /// plus rien ne peut changer sans une action — soit ici, soit dans un
    /// terminal, et une minute de retard n'a alors aucune conséquence.
    private var pollingInterval: Duration {
        if isPanelVisible { return .seconds(3) }
        return vm.state.isUsable ? .seconds(15) : .seconds(60)
    }

    private var canAutoStartVM: Bool {
        !isBusy && vm.state == .stopped && !needsOnboarding
    }

    // MARK: - Sondage

    // Trois cadences, parce que les trois sondages n'ont ni le même coût ni
    // le même rythme de changement. Mesures faites sur cette machine :
    //   outils        ~0,40 s  (dont `colima version` à 0,23 s)  — change à
    //                          l'installation, donc jamais en pratique
    //   état de la VM  0,10 s  — change quand on démarre ou arrête
    //   conteneurs     0,01 s  — change tout le temps, c'est ce qu'on regarde
    private var lastToolProbe: Date?
    private var lastVMProbe: Date?
    private static let vmProbeInterval: TimeInterval = 10

    func refreshTools() async {
        tools = await Toolchain.probe()
        lastToolProbe = Date()
    }

    private func isStale(_ date: Date?, _ interval: TimeInterval) -> Bool {
        date.map { Date().timeIntervalSince($0) > interval } ?? true
    }

    /// Force le prochain sondage à repartir de zéro, quel que soit le cache.
    private func invalidateProbes() {
        lastToolProbe = nil
        lastVMProbe = nil
    }

    func refresh() async {
        // Les outils ne s'installent pas tout seuls : on les sonde au
        // lancement, après chaque opération, et quand l'assistant s'ouvre.
        // Le faire périodiquement coûtait 0,40 s de processus par minute pour
        // constater qu'il ne s'était rien passé.
        if lastToolProbe == nil { await refreshTools() }

        // Pendant une manœuvre, l'état affiché est celui qu'on a posé
        // volontairement (« Démarrage… »). colima dirait encore « Arrêté »
        // pendant la minute que prend le réveil : le sondage attendra.
        if runningOperation == nil, isStale(lastVMProbe, Self.vmProbeInterval) {
            vm = await Colima.status()
            lastVMProbe = Date()
        }

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
            let isTransient =
                vm.state.isBusy
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
        trimLog()
    }

    /// Une installation Homebrew crache des milliers de lignes : on garde la
    /// fin, c'est là que se trouve l'erreur éventuelle.
    private func trimLog() {
        if log.count > Self.logLineLimit {
            log.removeFirst(log.count - Self.logLineLimit)
        }
    }

    private static let logLineLimit = 500

    func clearLog() { log.removeAll() }

    // MARK: - Actions

    /// Enveloppe commune : marque l'opération, capture l'erreur, rafraîchit.
    private func perform(_ operation: Operation, _ body: () async throws -> Void) async {
        guard runningOperation == nil else { return }
        runningOperation = operation
        lastError = nil
        // Filet de sécurité : une annulation ne doit pas laisser l'interface
        // verrouillée sur une opération fantôme.
        defer { runningOperation = nil }

        // Vide le tampon pendant que l'opération tourne : le journal avance
        // sous les yeux de l'utilisateur sans coûter un saut d'acteur par ligne.
        let drain = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                self?.drainPendingLines()
            }
        }

        do {
            try await body()
        } catch {
            lastError = error.localizedDescription
            appendLog(error.localizedDescription, isError: true)
        }

        drain.cancel()
        drainPendingLines()

        // L'opération est terminée avant le rafraîchissement, pas après :
        // sinon le sondage se croirait encore en pleine manœuvre et sauterait
        // la lecture de l'état, laissant l'affichage figé sur « Démarrage… ».
        runningOperation = nil

        // Une opération vient de changer l'état de la machine : aucun cache
        // de sondage n'est plus fiable.
        invalidateProbes()
        await refresh()
    }

    /// Tampon des lignes en attente d'affichage.
    ///
    /// `brew install` crache des milliers de lignes en quelques secondes. Une
    /// tâche `@MainActor` par ligne, c'était autant de sauts d'acteur et
    /// autant d'invalidations SwiftUI — pour du texte que personne ne lit
    /// ligne à ligne. On accumule hors acteur et on vide périodiquement.
    private let pendingLines = PendingLines()

    /// Collecte les lignes d'un processus depuis n'importe quel thread.
    private nonisolated func logCollector() -> @Sendable (String) -> Void {
        { [pendingLines] line in pendingLines.append(line) }
    }

    /// Déverse le tampon dans le journal, en un seul lot.
    private func drainPendingLines() {
        let lines = pendingLines.drain()
        guard !lines.isEmpty else { return }
        for line in lines {
            log.append(LogLine(text: line))
        }
        trimLog()
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
