import Foundation

/// Dialogue avec le démon Docker via le CLI.
enum Docker {

    private static func binary() throws -> String {
        guard let path = Shell.which("docker") else {
            throw Shell.Failure(command: "docker", message: "Le CLI docker n'est pas installé.")
        }
        return path
    }

    /// Une app GUI ne lit pas forcément le contexte docker actif : on pointe
    /// explicitement la socket de colima quand elle existe.
    private static func environment() -> [String: String] {
        let socket = Colima.dockerSocketPath()
        guard FileManager.default.fileExists(atPath: socket) else { return [:] }
        return ["DOCKER_HOST": "unix://" + socket]
    }

    /// La socket de la VM est-elle en place ?
    ///
    /// Tant qu'elle manque, `DOCKER_HOST` n'est pas posé et le CLI retombe sur
    /// `/var/run/docker.sock` — un chemin que Cocker n'utilise jamais, et qui
    /// donne un message d'erreur incompréhensible pour l'utilisateur.
    static var isSocketAvailable: Bool {
        FileManager.default.fileExists(atPath: Colima.dockerSocketPath())
    }

    /// docker ne distingue pas « démon injoignable » par son code de retour :
    /// il faut lire le message. Pendant qu'une VM se réveille, c'est un état
    /// d'attente, pas une panne.
    static func isDaemonUnreachable(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("cannot connect to the docker daemon")
            || lowered.contains("failed to connect to the docker api")
            || lowered.contains("is the docker daemon running")
            || lowered.contains("no such file or directory")
    }

    // MARK: - Conteneurs

    /// Tous les conteneurs, en marche ou non.
    static func containers() async throws -> [Container] {
        let docker = try binary()
        let result = try await Shell.run(
            docker,
            ["ps", "--all", "--no-trunc", "--format", "{{json .}}"],
            environment: environment()
        )
        guard result.isSuccess else {
            throw Shell.Failure(command: "docker ps", message: result.failureMessage)
        }
        return parseContainers(from: result.stdout)
    }

    /// Séparé de l'appel au CLI pour être testable sans démon Docker.
    /// C'est le morceau qui casse quand docker change le format de sa sortie.
    static func parseContainers(from output: String) -> [Container] {
        output
            .split(separator: "\n")
            .compactMap { RawContainer.decode(String($0))?.asContainer() }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Regroupe par projet Compose. Les conteneurs isolés finissent ensemble
    /// dans un groupe fourre-tout, placé en dernier.
    static func group(_ containers: [Container]) -> [ContainerGroup] {
        var byProject: [String: [Container]] = [:]
        for container in containers {
            let key = container.project?.isEmpty == false
                ? container.project!
                : ContainerGroup.looseName
            byProject[key, default: []].append(container)
        }

        return byProject
            .map { ContainerGroup(name: $0.key, containers: $0.value) }
            .sorted { left, right in
                // Le fourre-tout passe toujours en dernier.
                if left.isLoose != right.isLoose { return right.isLoose }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    // MARK: - Actions

    enum Action: String {
        case start, stop, restart

        var label: String {
            switch self {
            case .start: "Démarrer"
            case .stop: "Arrêter"
            case .restart: "Redémarrer"
            }
        }
    }

    static func perform(_ action: Action, on containerID: String) async throws {
        let docker = try binary()
        try await Shell.runOrThrow(docker, [action.rawValue, containerID], environment: environment())
    }

    /// Applique une action à tout un projet Compose, en parallèle.
    static func perform(_ action: Action, on group: ContainerGroup) async throws {
        try await withThrowingTaskGroup(of: Void.self) { tasks in
            for container in group.containers {
                tasks.addTask { try await perform(action, on: container.id) }
            }
            try await tasks.waitForAll()
        }
    }

    static func logs(for containerID: String, lines: Int = 300) async throws -> String {
        let docker = try binary()
        let result = try await Shell.run(
            docker,
            ["logs", "--tail", String(lines), containerID],
            environment: environment()
        )
        // Beaucoup d'images écrivent leurs logs sur stderr : les deux comptent.
        let combined = result.stdout + result.stderr
        guard result.isSuccess || !combined.isEmpty else {
            throw Shell.Failure(command: "docker logs", message: result.failureMessage)
        }
        return combined
    }

    // MARK: - Disque

    static func diskUsage() async throws -> DiskUsage {
        let docker = try binary()
        let result = try await Shell.run(
            docker,
            ["system", "df", "--format", "{{json .}}"],
            environment: environment()
        )
        guard result.isSuccess else {
            throw Shell.Failure(command: "docker system df", message: result.failureMessage)
        }
        return parseDiskUsage(from: result.stdout)
    }

    /// Séparé de l'appel au CLI pour être testable.
    static func parseDiskUsage(from output: String) -> DiskUsage {
        var usage = DiskUsage()
        for line in output.split(separator: "\n") {
            guard let row = RawDiskRow.decode(String(line)) else { continue }
            let size = ByteSize.parse(row.size)
            switch row.kind.lowercased() {
            case "images": usage.imagesBytes = size
            case "containers": usage.containersBytes = size
            case "local volumes": usage.volumesBytes = size
            default: break
            }
            usage.reclaimableBytes += ByteSize.parse(row.reclaimable)
        }
        return usage
    }

    /// Supprime les objets inutilisés. Destructif : l'appelant confirme.
    static func prune(includeVolumes: Bool, onOutput: @escaping @Sendable (String) -> Void) async throws {
        let docker = try binary()
        var arguments = ["system", "prune", "--force"]
        if includeVolumes { arguments.append("--volumes") }
        onOutput("$ docker " + arguments.joined(separator: " "))
        try await Shell.runOrThrow(docker, arguments, environment: environment(), onOutput: onOutput)
    }
}

// MARK: - Décodage

/// La ligne JSON produite par `docker ps --format '{{json .}}'`.
private struct RawContainer: Decodable {
    var id: String?
    var names: String?
    var image: String?
    var state: String?
    var status: String?
    var ports: String?
    var labels: String?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case names = "Names"
        case image = "Image"
        case state = "State"
        case status = "Status"
        case ports = "Ports"
        case labels = "Labels"
    }

    static func decode(_ line: String) -> RawContainer? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RawContainer.self, from: data)
    }

    func asContainer() -> Container? {
        guard let id, !id.isEmpty else { return nil }
        let parsedLabels = Self.parseLabels(labels)
        // `docker ps` sépare les noms par une virgule quand un conteneur en a
        // plusieurs ; le premier suffit.
        let name = names?.split(separator: ",").first.map(String.init) ?? String(id.prefix(12))

        return Container(
            id: id,
            name: name,
            image: image ?? "—",
            state: Container.State(rawValue: state?.lowercased() ?? "") ?? .unknown,
            status: status ?? "",
            ports: Self.parsePorts(ports),
            project: parsedLabels["com.docker.compose.project"],
            service: parsedLabels["com.docker.compose.service"]
        )
    }

    /// `Labels` est une liste `clé=valeur` séparée par des virgules.
    private static func parseLabels(_ raw: String?) -> [String: String] {
        guard let raw, !raw.isEmpty else { return [:] }
        var labels: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            guard let separator = pair.firstIndex(of: "=") else { continue }
            let key = String(pair[pair.startIndex..<separator])
            let value = String(pair[pair.index(after: separator)...])
            labels[key] = value
        }
        return labels
    }

    /// `Ports` ressemble à « 0.0.0.0:8080->80/tcp, :::8080->80/tcp ».
    /// Les deux entrées décrivent la même publication : on déduplique.
    private static func parsePorts(_ raw: String?) -> [PortMapping] {
        guard let raw, !raw.isEmpty else { return [] }
        var found: [PortMapping] = []
        var seen = Set<String>()

        for entry in raw.split(separator: ",") {
            let text = entry.trimmingCharacters(in: .whitespaces)
            guard let arrow = text.range(of: "->") else { continue }

            let hostSide = String(text[text.startIndex..<arrow.lowerBound])
            let containerSide = String(text[arrow.upperBound...])

            // Côté hôte : « ip:port », l'IPv6 contient elle-même des « : ».
            guard let hostPort = Int(hostSide.split(separator: ":").last ?? "") else { continue }

            let parts = containerSide.split(separator: "/")
            guard let containerPort = Int(parts.first ?? "") else { continue }
            let protocolName = parts.count > 1 ? String(parts[1]) : "tcp"

            let mapping = PortMapping(
                hostPort: hostPort,
                containerPort: containerPort,
                protocolName: protocolName
            )
            if seen.insert(mapping.id).inserted { found.append(mapping) }
        }
        return found.sorted { $0.hostPort < $1.hostPort }
    }
}

private struct RawDiskRow: Decodable {
    var kind: String
    var size: String
    var reclaimable: String

    enum CodingKeys: String, CodingKey {
        case kind = "Type"
        case size = "Size"
        case reclaimable = "Reclaimable"
    }

    static func decode(_ line: String) -> RawDiskRow? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RawDiskRow.self, from: data)
    }
}

/// Docker rend ses tailles en texte (« 1.23GB », « 890MB (45%) »).
enum ByteSize {
    static func parse(_ text: String) -> Int64 {
        // On coupe avant l'éventuel pourcentage entre parenthèses.
        let head = text.split(separator: "(").first.map(String.init) ?? text
        let trimmed = head.trimmingCharacters(in: .whitespaces)

        let digits = trimmed.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(digits) else { return 0 }

        let unit = trimmed.dropFirst(digits.count).trimmingCharacters(in: .whitespaces).uppercased()
        let multiplier: Double = switch unit {
        case "B", "": 1
        case "KB", "KIB": 1_024
        case "MB", "MIB": 1_048_576
        case "GB", "GIB": 1_073_741_824
        case "TB", "TIB": 1_099_511_627_776
        default: 1
        }
        return Int64(value * multiplier)
    }

    static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}
