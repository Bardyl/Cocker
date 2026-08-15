import Foundation

/// Découverte et installation des outils dont Cocker dépend.
enum Toolchain {

    /// Inspecte le disque et renvoie l'état de chaque outil.
    static func probe() async -> [Tool] {
        var tools: [Tool] = []
        for kind in Tool.Kind.allCases {
            tools.append(await probe(kind))
        }
        return tools
    }

    static func probe(_ kind: Tool.Kind) async -> Tool {
        switch kind {
        case .homebrew:
            guard let path = Shell.which("brew") else { return Tool(kind: kind) }
            let version = try? await Shell.run(path, ["--version"]).stdout
            return Tool(kind: kind, path: path, version: firstLine(version))

        case .colima:
            guard let path = Shell.which("colima") else { return Tool(kind: kind) }
            let version = try? await Shell.run(path, ["version"]).stdout
            return Tool(kind: kind, path: path, version: firstLine(version))

        case .docker:
            guard let path = Shell.which("docker") else { return Tool(kind: kind) }
            let version = try? await Shell.run(path, ["--version"]).stdout
            return Tool(kind: kind, path: path, version: firstLine(version))

        case .compose, .buildx:
            // Les plugins ne sont pas des exécutables du PATH : ils vivent dans
            // des dossiers `cli-plugins`.
            let binary = pluginBinaryName(kind)
            guard let path = pluginPath(named: binary) else { return Tool(kind: kind) }

            let isLinked = dockerSearchPaths.contains { path.hasPrefix($0 + "/") }
            var version: String?
            if isLinked, let docker = Shell.which("docker") {
                let subcommand = kind == .compose ? "compose" : "buildx"
                version = try? await Shell.run(docker, [subcommand, "version"]).stdout
            }
            return Tool(kind: kind, path: path, version: firstLine(version), isLinked: isLinked)
        }
    }

    static func pluginBinaryName(_ kind: Tool.Kind) -> String {
        kind == .compose ? "docker-compose" : "docker-buildx"
    }

    /// Dossier personnel des plugins : le seul que le CLI docker fouille à
    /// coup sûr, quelle que soit l'origine de l'installation.
    static var userPluginDirectory: String {
        NSHomeDirectory() + "/.docker/cli-plugins"
    }

    /// Les dossiers que le CLI docker fouille réellement.
    /// `/opt/homebrew/…` n'en fait pas partie : c'est toute l'origine du
    /// problème que `linkPlugin(_:)` répare.
    private static var dockerSearchPaths: [String] {
        [
            userPluginDirectory,
            "/usr/local/lib/docker/cli-plugins",
            "/usr/local/libexec/docker/cli-plugins",
            "/usr/lib/docker/cli-plugins",
            "/usr/libexec/docker/cli-plugins",
        ]
    }

    /// Tous les emplacements possibles, y compris ceux de Homebrew.
    private static var allPluginPaths: [String] {
        dockerSearchPaths + [
            "/opt/homebrew/lib/docker/cli-plugins",
            "/opt/homebrew/libexec/docker/cli-plugins",
        ]
    }

    private static func pluginPath(named binary: String) -> String? {
        for directory in allPluginPaths {
            let candidate = directory + "/" + binary
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Rend un plugin visible du CLI docker en le liant dans `~/.docker/cli-plugins`.
    ///
    /// Un lien symbolique plutôt qu'une copie : `brew upgrade` met alors le
    /// plugin à jour sans que Cocker ait à repasser derrière.
    static func linkPlugin(_ kind: Tool.Kind, onOutput: @escaping @Sendable (String) -> Void) throws {
        let binary = pluginBinaryName(kind)
        guard let source = pluginPath(named: binary) else {
            throw Shell.Failure(command: "link", message: "\(binary) est introuvable.")
        }

        let fileManager = FileManager.default
        let destination = userPluginDirectory + "/" + binary

        try fileManager.createDirectory(
            atPath: userPluginDirectory,
            withIntermediateDirectories: true
        )

        // Un lien cassé ou périmé occupe la place sans rien résoudre.
        if fileManager.fileExists(atPath: destination)
            || (try? fileManager.destinationOfSymbolicLink(atPath: destination)) != nil {
            try fileManager.removeItem(atPath: destination)
        }

        try fileManager.createSymbolicLink(atPath: destination, withDestinationPath: source)
        onOutput("$ ln -sf \(source) \(destination)")
    }

    private static func firstLine(_ text: String?) -> String? {
        guard let line = text?
            .split(separator: "\n")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty })
        else { return nil }
        return line
    }

    // MARK: - Installation

    /// Installe une formule Homebrew, en diffusant sa sortie ligne par ligne.
    static func install(_ kind: Tool.Kind, onOutput: @escaping @Sendable (String) -> Void) async throws {
        guard let formula = kind.formula else {
            throw Shell.Failure(
                command: "brew",
                message: "Homebrew ne peut pas s'installer lui-même depuis Cocker."
            )
        }
        guard let brew = Shell.which("brew") else {
            throw Shell.Failure(
                command: "brew",
                message: "Homebrew est introuvable. Installe-le d'abord depuis brew.sh."
            )
        }

        onOutput("$ brew install \(formula)")
        // NONINTERACTIVE : brew ne doit jamais attendre une touche, personne
        // ne peut lui répondre depuis une app sans terminal.
        try await Shell.runOrThrow(
            brew,
            ["install", formula],
            environment: ["NONINTERACTIVE": "1", "HOMEBREW_NO_AUTO_UPDATE": "1"],
            onOutput: onOutput
        )

        // Homebrew pose les plugins hors de portée du CLI docker : sans ce
        // lien, `docker compose` reste une commande inconnue.
        if kind == .compose || kind == .buildx {
            try linkPlugin(kind, onOutput: onOutput)
        }
    }

    /// Commande à coller dans un terminal pour installer Homebrew.
    static let homebrewInstallCommand =
        #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
}
