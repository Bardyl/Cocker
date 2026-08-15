import Foundation

/// Pilotage de la VM colima.
enum Colima {

    static let profile = "default"

    private static func binary() throws -> String {
        guard let path = Shell.which("colima") else {
            throw Shell.Failure(command: "colima", message: "Colima is not installed.")
        }
        return path
    }

    // MARK: - Lecture de l'état

    /// Interroge colima. Ne lève jamais : une VM absente est un état, pas une
    /// erreur, et l'app doit pouvoir l'afficher.
    static func status() async -> VMStatus {
        guard let colima = Shell.which("colima") else {
            return VMStatus(state: .missing)
        }

        // `list --json` et pas `status --json` : le premier coûte 0,10 s, le
        // second 0,37 s, et il échoue quand la VM dort — on payait alors les
        // deux. `list` répond dans tous les cas et porte déjà tout ce que
        // l'interface montre : état, cœurs, mémoire, disque, arch, moteur.
        guard let listed = try? await Shell.run(colima, ["list", "--json"]), listed.isSuccess else {
            return VMStatus(state: .notCreated)
        }
        return parseList(from: listed.stdout) ?? VMStatus(state: .notCreated)
    }

    /// Sortie de `colima list --json` : une ligne JSON par profil, présente
    /// même à l'arrêt.
    static func parseList(from output: String) -> VMStatus? {
        Snapshot.decodeAll(output)
            .first { $0.name == profile }?
            .asStatus(fallbackState: .stopped)
    }

    /// Chemin de la socket docker exposée par la VM.
    static func dockerSocketPath() -> String {
        NSHomeDirectory() + "/.colima/\(profile)/docker.sock"
    }

    // MARK: - Cycle de vie

    /// Démarre la VM avec les ressources demandées.
    ///
    /// `colima start` est idempotent : sur une VM déjà créée il applique les
    /// nouveaux paramètres, ce qui sert aussi de « redimensionnement ».
    static func start(
        resources: VMResources,
        useRosetta: Bool,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws {
        let colima = try binary()
        var arguments = [
            "start",
            "--profile", profile,
            "-c", String(resources.cpus),
            "-m", formatMemory(resources.memoryGiB),
            "-d", String(resources.diskGiB),
            "--runtime", "docker",
            "--activate",
        ]
        if useRosetta {
            arguments += ["--vm-type", "vz", "--vz-rosetta"]
        }

        onOutput("$ colima " + arguments.joined(separator: " "))
        try await Shell.runOrThrow(colima, arguments, onOutput: onOutput)
    }

    static func stop(onOutput: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        let colima = try binary()
        onOutput("$ colima stop")
        try await Shell.runOrThrow(colima, ["stop", "--profile", profile], onOutput: onOutput)
    }

    static func restart(
        resources: VMResources,
        useRosetta: Bool,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws {
        try await stop(onOutput: onOutput)
        try await start(resources: resources, useRosetta: useRosetta, onOutput: onOutput)
    }

    /// colima veut un entier quand la valeur est ronde, sinon un décimal.
    private static func formatMemory(_ giB: Double) -> String {
        if giB == giB.rounded() { return String(Int(giB)) }
        return String(format: "%.1f", giB)
    }
}

// MARK: - Décodage

/// Reflet de la sortie JSON de colima.
///
/// `list --json` et `status --json` ne parlent pas tout à fait la même langue :
/// le premier dit `name`/`cpus` et porte un `status`, le second dit
/// `display_name`/`cpu` et n'en a pas. On accepte les deux jeux de clés, et
/// tout est optionnel pour qu'une clé manquante n'en fasse pas perdre d'autres.
private struct Snapshot: Decodable {
    var name: String?
    var status: String?
    var arch: String?
    var cpus: Int?
    var memory: Int64?
    var disk: Int64?
    var runtime: String?
    var address: String?
    var dockerSocket: String?

    enum CodingKeys: String, CodingKey {
        case name, status, arch, cpus, memory, disk, runtime, address
        case displayName = "display_name"
        case cpu
        case dockerSocket = "docker_socket"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name =
            try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .displayName)
        cpus =
            try container.decodeIfPresent(Int.self, forKey: .cpus)
            ?? container.decodeIfPresent(Int.self, forKey: .cpu)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        arch = try container.decodeIfPresent(String.self, forKey: .arch)
        memory = try container.decodeIfPresent(Int64.self, forKey: .memory)
        disk = try container.decodeIfPresent(Int64.self, forKey: .disk)
        runtime = try container.decodeIfPresent(String.self, forKey: .runtime)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        dockerSocket = try container.decodeIfPresent(String.self, forKey: .dockerSocket)
    }

    /// colima écrit un objet JSON par ligne.
    static func decodeAll(_ text: String) -> [Snapshot] {
        let decoder = JSONDecoder()
        return
            text
            .split(separator: "\n")
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else {
                    return nil
                }
                return try? decoder.decode(Snapshot.self, from: data)
            }
    }

    func asStatus(fallbackState: VMState) -> VMStatus {
        var status = VMStatus()
        status.state = Self.parseState(self.status) ?? fallbackState
        status.architecture = arch
        status.runtime = runtime
        status.dockerSocket = dockerSocket ?? Colima.dockerSocketPath()
        status.resources = VMResources(
            cpus: cpus ?? VMResources.default.cpus,
            memoryGiB: Self.toGiB(memory) ?? VMResources.default.memoryGiB,
            diskGiB: Self.toGiB(disk).map { Int($0.rounded()) } ?? VMResources.default.diskGiB
        )
        return status
    }

    private static func parseState(_ raw: String?) -> VMState? {
        switch raw?.lowercased() {
        case "running": .running
        case "stopped": .stopped
        case "broken": .stopped
        default: nil
        }
    }

    /// colima rapporte des octets ; les versions anciennes rapportaient des
    /// GiB. Au-delà de 1024 la valeur ne peut être que des octets.
    private static func toGiB(_ value: Int64?) -> Double? {
        guard let value, value > 0 else { return nil }
        if value < 1024 { return Double(value) }
        return Double(value) / 1_073_741_824
    }
}
