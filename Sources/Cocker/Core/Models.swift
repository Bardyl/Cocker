import Foundation

// MARK: - Outils

/// Un outil en ligne de commande dont Cocker dépend.
struct Tool: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case homebrew
        case colima
        case docker
        case compose
        case buildx

        /// Nom de la formule Homebrew. `nil` pour Homebrew lui-même, qui
        /// s'installe autrement.
        var formula: String? {
            switch self {
            case .homebrew: nil
            case .colima: "colima"
            case .docker: "docker"
            case .compose: "docker-compose"
            case .buildx: "docker-buildx"
            }
        }

        var displayName: String {
            switch self {
            case .homebrew: "Homebrew"
            case .colima: "Colima"
            case .docker: "Docker CLI"
            case .compose: "Docker Compose"
            case .buildx: "Docker Buildx"
            }
        }

        var summary: String {
            switch self {
            case .homebrew: "Le gestionnaire de paquets qui installe tout le reste."
            case .colima: "La machine virtuelle qui fait tourner le moteur Docker."
            case .docker: "La commande `docker` que tu utilises au quotidien."
            case .compose: "Lance des piles multi-conteneurs décrites en YAML."
            case .buildx: "Moteur de build moderne, requis par la plupart des images."
            }
        }

        /// Un environnement Docker utilisable exige au minimum ces outils.
        var isRequired: Bool {
            switch self {
            case .homebrew, .colima, .docker: true
            case .compose, .buildx: false
            }
        }
    }

    var kind: Kind
    var path: String?
    var version: String?
    /// Faux quand le binaire existe mais que le CLI docker ne le trouve pas :
    /// Homebrew pose ses plugins dans un dossier que docker ne fouille pas.
    var isLinked: Bool = true

    var id: Kind { kind }
    var isInstalled: Bool { path != nil }
    var isReady: Bool { isInstalled && isLinked }
    /// Installé mais inutilisable : un lien symbolique suffit à le réparer.
    var needsLinking: Bool { isInstalled && !isLinked }
}

// MARK: - Machine virtuelle

/// État de la VM colima.
enum VMState: Equatable, Sendable {
    case unknown
    case missing        // colima n'est pas installé
    case notCreated     // installé, mais aucun profil n'existe encore
    case stopped
    case starting
    case running
    case stopping

    var label: String {
        switch self {
        case .unknown: "Vérification…"
        case .missing: "Non installé"
        case .notCreated: "Jamais démarré"
        case .stopped: "Arrêté"
        case .starting: "Démarrage…"
        case .running: "En marche"
        case .stopping: "Arrêt…"
        }
    }

    var isBusy: Bool { self == .starting || self == .stopping }
    var isUsable: Bool { self == .running }
}

/// Ressources allouées à la VM. Ce sont les valeurs que l'utilisateur pilote.
struct VMResources: Equatable, Sendable {
    var cpus: Int
    var memoryGiB: Double
    var diskGiB: Int

    static let `default` = VMResources(cpus: 4, memoryGiB: 8, diskGiB: 60)
}

/// Instantané de la VM tel que colima le rapporte.
struct VMStatus: Equatable, Sendable {
    var state: VMState = .unknown
    var resources: VMResources = .default
    var runtime: String?
    var architecture: String?
    var dockerSocket: String?
    var ipAddress: String?

    static let unknown = VMStatus()
}

// MARK: - Conteneurs

/// Un port publié sur l'hôte.
struct PortMapping: Hashable, Sendable, Identifiable {
    var hostPort: Int
    var containerPort: Int
    var protocolName: String

    var id: String { "\(hostPort)/\(containerPort)/\(protocolName)" }
    var label: String { "\(hostPort) → \(containerPort)" }

    /// Seuls les ports TCP valent la peine d'être ouverts dans un navigateur.
    var isWebLikely: Bool { protocolName == "tcp" }
    var localURL: URL? { URL(string: "http://localhost:\(hostPort)") }
}

struct Container: Identifiable, Hashable, Sendable {
    enum State: String, Sendable {
        case created
        case restarting
        case running
        case removing
        case paused
        case exited
        case dead
        case unknown

        var isRunning: Bool { self == .running || self == .restarting }

        var label: String {
            switch self {
            case .created: "Créé"
            case .restarting: "Redémarre"
            case .running: "En marche"
            case .removing: "Suppression"
            case .paused: "En pause"
            case .exited: "Arrêté"
            case .dead: "Mort"
            case .unknown: "Inconnu"
            }
        }
    }

    var id: String
    var name: String
    var image: String
    var state: State
    var status: String
    var ports: [PortMapping]
    /// Projet Compose (label `com.docker.compose.project`), s'il y en a un.
    var project: String?
    /// Service Compose au sein du projet.
    var service: String?

    /// Nom court : dans un projet Compose, le nom du service suffit.
    var displayName: String {
        if let service, !service.isEmpty { return service }
        return name
    }
}

/// Des conteneurs regroupés par projet Compose.
struct ContainerGroup: Identifiable, Hashable, Sendable {
    var name: String
    var containers: [Container]

    var id: String { name }
    var runningCount: Int { containers.filter { $0.state.isRunning }.count }
    var isRunning: Bool { runningCount > 0 }

    /// Groupe fourre-tout pour les conteneurs lancés hors Compose.
    static let looseName = "Sans projet"
    var isLoose: Bool { name == Self.looseName }
}

// MARK: - Disque

/// Sortie de `docker system df`, pour la vue « ressources ».
struct DiskUsage: Equatable, Sendable {
    var imagesBytes: Int64 = 0
    var containersBytes: Int64 = 0
    var volumesBytes: Int64 = 0
    var reclaimableBytes: Int64 = 0

    var totalBytes: Int64 { imagesBytes + containersBytes + volumesBytes }
}
