import Foundation
import Observation

/// Réglages persistés dans `UserDefaults`.
///
/// Ce sont les ressources *voulues* par l'utilisateur ; `VMStatus` décrit
/// celles réellement en vigueur. L'écart entre les deux est ce qui justifie le
/// bouton « Appliquer » des réglages.
@MainActor
@Observable
final class Preferences {

    private enum Key {
        static let cpus = "vm.cpus"
        static let memory = "vm.memoryGiB"
        static let disk = "vm.diskGiB"
        static let rosetta = "vm.rosetta"
        static let startVMAtLaunch = "app.startVMAtLaunch"
        static let onboardingDone = "app.onboardingCompleted"
        static let showStoppedContainers = "ui.showStoppedContainers"
        static let checksForUpdates = "updates.enabled"
        static let language = "ui.language"
    }

    private let defaults: UserDefaults

    var desiredResources: VMResources {
        didSet {
            defaults.set(desiredResources.cpus, forKey: Key.cpus)
            defaults.set(desiredResources.memoryGiB, forKey: Key.memory)
            defaults.set(desiredResources.diskGiB, forKey: Key.disk)
        }
    }

    var useRosetta: Bool {
        didSet { defaults.set(useRosetta, forKey: Key.rosetta) }
    }

    /// Démarre la VM dès que Cocker se lance — c'est ce qui rend `docker`
    /// utilisable au login sans rien taper.
    var startVMAtLaunch: Bool {
        didSet { defaults.set(startVMAtLaunch, forKey: Key.startVMAtLaunch) }
    }

    var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingDone) }
    }

    var showStoppedContainers: Bool {
        didSet { defaults.set(showStoppedContainers, forKey: Key.showStoppedContainers) }
    }

    /// La seule requête réseau que Cocker émet. Activée par défaut, mais
    /// débrayable : personne ne devrait avoir à subir un appel sortant qu'il
    /// n'a pas demandé.
    var checksForUpdates: Bool {
        didSet { defaults.set(checksForUpdates, forKey: Key.checksForUpdates) }
    }

    /// Langue de l'interface. Écrire aussi `AppleLanguages` sert aux chaînes
    /// résolues hors d'une vue, que l'environnement SwiftUI n'atteint pas.
    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Key.language)
            if let codes = language.preferredLanguages {
                defaults.set(codes, forKey: "AppleLanguages")
            } else {
                defaults.removeObject(forKey: "AppleLanguages")
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let fallback = Self.hardwareDefaults()
        let cpus = defaults.object(forKey: Key.cpus) as? Int ?? fallback.cpus
        let memory = defaults.object(forKey: Key.memory) as? Double ?? fallback.memoryGiB
        let disk = defaults.object(forKey: Key.disk) as? Int ?? fallback.diskGiB

        self.desiredResources = VMResources(cpus: cpus, memoryGiB: memory, diskGiB: disk)
        self.useRosetta = defaults.object(forKey: Key.rosetta) as? Bool ?? false
        self.startVMAtLaunch = defaults.object(forKey: Key.startVMAtLaunch) as? Bool ?? true
        self.onboardingCompleted = defaults.bool(forKey: Key.onboardingDone)
        self.showStoppedContainers =
            defaults.object(forKey: Key.showStoppedContainers) as? Bool ?? true
        self.checksForUpdates = defaults.object(forKey: Key.checksForUpdates) as? Bool ?? true
        self.language =
            AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .system
    }

    /// Aligne les préférences sur ce que la VM utilise déjà, pour ne pas
    /// proposer d'« appliquer » un changement que l'utilisateur n'a pas demandé.
    func adopt(_ resources: VMResources) {
        desiredResources = resources
    }

    /// Valeurs de départ raisonnables : la moitié de la machine, sans
    /// descendre sous un minimum utilisable.
    static func hardwareDefaults() -> VMResources {
        let cores = max(2, ProcessInfo.processInfo.processorCount / 2)
        let physicalGiB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let memory = max(4, (physicalGiB / 2).rounded(.down))
        return VMResources(cpus: cores, memoryGiB: memory, diskGiB: 60)
    }

    /// Bornes hautes proposées dans l'interface : au-delà, la VM affame macOS.
    static var maxCPUs: Int { max(2, ProcessInfo.processInfo.processorCount) }

    static var maxMemoryGiB: Double {
        let physicalGiB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return max(4, (physicalGiB - 4).rounded(.down))
    }
}
