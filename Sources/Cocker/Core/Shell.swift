import Foundation

/// Exécution de processus externes.
///
/// Une app lancée par le Finder n'hérite pas du `PATH` du shell : Homebrew,
/// colima et docker sont invisibles si on ne reconstruit pas l'environnement
/// nous-mêmes. Tout passe donc par `Shell.environment()`.
enum Shell {

    struct Result: Sendable {
        var exitCode: Int32
        var stdout: String
        var stderr: String

        var isSuccess: Bool { exitCode == 0 }

        /// Message d'erreur le plus parlant disponible.
        var failureMessage: String {
            let stderrTrimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderrTrimmed.isEmpty { return stderrTrimmed }
            let stdoutTrimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stdoutTrimmed.isEmpty { return stdoutTrimmed }
            return "The process exited with code \(exitCode)."
        }
    }

    struct Failure: LocalizedError {
        var command: String
        var message: String
        var errorDescription: String? { "\(command) : \(message)" }
    }

    /// Répertoires fouillés pour retrouver un exécutable, dans l'ordre.
    /// Homebrew d'abord : sur Apple Silicon il vit dans `/opt/homebrew`.
    static let searchPaths = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    /// Chemin absolu d'un outil, ou `nil` s'il n'est pas installé.
    static func which(_ name: String) -> String? {
        for directory in searchPaths {
            let candidate = directory + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    static func environment(extra: [String: String] = [:]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let inherited = environment["PATH"]?.split(separator: ":").map(String.init) ?? []

        var seen = Set<String>()
        var path: [String] = []
        for directory in searchPaths + inherited where seen.insert(directory).inserted {
            path.append(directory)
        }

        environment["PATH"] = path.joined(separator: ":")
        environment["HOME"] = NSHomeDirectory()
        for (key, value) in extra { environment[key] = value }
        return environment
    }

    /// Lance `executable` et attend sa fin.
    ///
    /// `onOutput` reçoit chaque ligne (stdout et stderr confondus) au fil de
    /// l'eau : c'est ce qui alimente le journal de l'onboarding.
    @discardableResult
    static func run(
        _ executable: String,
        _ arguments: [String],
        environment extra: [String: String] = [:],
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> Result {
        let run = ProcessRun()
        run.process.executableURL = URL(fileURLWithPath: executable)
        run.process.arguments = arguments
        run.process.environment = environment(extra: extra)
        run.process.standardInput = FileHandle.nullDevice
        run.process.standardOutput = run.outputPipe
        run.process.standardError = run.errorPipe

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                run.outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    run.stdout.append(handle.availableData, emitTo: onOutput)
                }
                run.errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    run.stderr.append(handle.availableData, emitTo: onOutput)
                }
                run.process.terminationHandler = { process in
                    run.finish(onOutput: onOutput)
                    continuation.resume(
                        returning: Result(
                            exitCode: process.terminationStatus,
                            stdout: run.stdout.text,
                            stderr: run.stderr.text
                        )
                    )
                }
                do {
                    try run.process.run()
                } catch {
                    run.detachHandlers()
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            run.terminate()
        }
    }

    /// Variante qui échoue si le code de retour n'est pas 0.
    @discardableResult
    static func runOrThrow(
        _ executable: String,
        _ arguments: [String],
        environment extra: [String: String] = [:],
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> Result {
        let result = try await run(executable, arguments, environment: extra, onOutput: onOutput)
        guard result.isSuccess else {
            let name = (executable as NSString).lastPathComponent
            throw Failure(
                command: ([name] + arguments).joined(separator: " "),
                message: result.failureMessage
            )
        }
        return result
    }
}

/// Boîte non isolée qui porte le `Process` et ses tuyaux.
///
/// `Process`, `Pipe` et `FileHandle` ne sont pas `Sendable` ; les regrouper ici
/// permet de ne capturer qu'un seul objet dans les closures de lecture.
private final class ProcessRun: @unchecked Sendable {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    let stdout = LineBuffer()
    let stderr = LineBuffer()

    func detachHandlers() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
    }

    func finish(onOutput: (@Sendable (String) -> Void)?) {
        detachHandlers()
        stdout.append(outputPipe.fileHandleForReading.availableData, emitTo: onOutput)
        stderr.append(errorPipe.fileHandleForReading.availableData, emitTo: onOutput)
        stdout.flush(emitTo: onOutput)
        stderr.flush(emitTo: onOutput)
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}

/// Accumule des octets et les découpe en lignes complètes.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var accumulated = ""
    private var pending = ""

    /// Plafond de ce qu'on retient. Un `brew install` produit plusieurs Mo que
    /// personne ne relira, et l'appelant n'exploite `text` que pour analyser
    /// une sortie courte ou récupérer un message d'erreur — lequel se trouve
    /// à la fin. On coupe donc par le début, sur une frontière de ligne, pour
    /// ne jamais livrer un fragment de JSON.
    private static let retentionLimit = 1 << 20

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return accumulated
    }

    func append(_ data: Data, emitTo onOutput: (@Sendable (String) -> Void)?) {
        guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }

        lock.lock()
        accumulated += chunk
        trimAccumulatedIfNeeded()
        pending += chunk
        var lines: [String] = []
        while let newline = pending.firstIndex(of: "\n") {
            lines.append(String(pending[pending.startIndex..<newline]))
            pending = String(pending[pending.index(after: newline)...])
        }
        lock.unlock()

        guard let onOutput else { return }
        for line in lines { onOutput(line) }
    }

    /// À appeler verrou tenu.
    private func trimAccumulatedIfNeeded() {
        guard accumulated.utf8.count > Self.retentionLimit else { return }

        let overflow = accumulated.utf8.count - Self.retentionLimit
        guard
            let start = accumulated.utf8.index(
                accumulated.utf8.startIndex, offsetBy: overflow,
                limitedBy: accumulated.utf8.endIndex
            )?.samePosition(in: accumulated)
        else {
            accumulated = ""
            return
        }

        // On repart à la ligne suivante : couper au milieu d'une ligne
        // produirait un fragment que le décodeur JSON refuserait.
        if let newline = accumulated[start...].firstIndex(of: "\n") {
            accumulated = String(accumulated[accumulated.index(after: newline)...])
        } else {
            accumulated = String(accumulated[start...])
        }
    }

    func flush(emitTo onOutput: (@Sendable (String) -> Void)?) {
        lock.lock()
        let remainder = pending
        pending = ""
        lock.unlock()

        guard let onOutput, !remainder.isEmpty else { return }
        onOutput(remainder)
    }
}

/// Tampon de lignes partagé entre un processus et l'acteur principal.
///
/// Volontairement une classe verrouillée plutôt qu'un acteur : les lignes
/// arrivent depuis les callbacks de `FileHandle`, qui ne sont pas asynchrones.
/// Un acteur imposerait un `Task` par ligne, exactement ce qu'on cherche à
/// éviter.
final class PendingLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    /// Au-delà, on jette le plus ancien : personne ne lira les dix mille
    /// premières lignes d'un `brew install`, et le journal les tronquerait
    /// de toute façon.
    private static let limit = 2_000

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
        if lines.count > Self.limit {
            lines.removeFirst(lines.count - Self.limit)
        }
    }

    func drain() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let drained = lines
        lines.removeAll(keepingCapacity: true)
        return drained
    }
}
