import Foundation
import Observation

/// Vérification des mises à jour via les releases GitHub.
///
/// Volontairement sans Sparkle : Sparkle suppose des paquets signés et une clé
/// EdDSA à gérer, ce qui n'a de sens qu'une fois l'app notarisée. En attendant,
/// on se contente de dire qu'une version existe et d'ouvrir sa page.
@MainActor
@Observable
final class Updater {

    static let repository = "Bardyl/Cocker"
    static let releasesURL = URL(string: "https://github.com/\(repository)/releases/latest")!

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed(String)
    }

    private(set) var state: State = .idle

    /// Version de l'app telle qu'annoncée par son bundle.
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private let defaults: UserDefaults
    private static let lastCheckKey = "updates.lastCheck"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Vérification discrète au lancement, au plus une fois par jour.
    /// L'utilisateur peut la couper : c'est la seule requête réseau que
    /// Cocker émet, et il a le droit de ne pas la vouloir.
    func checkQuietlyIfDue(enabled: Bool) async {
        guard enabled else { return }

        let now = Date()
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           now.timeIntervalSince(last) < 24 * 3600 {
            return
        }
        defaults.set(now, forKey: Self.lastCheckKey)
        await check()
    }

    func check() async {
        state = .checking
        do {
            let latest = try await fetchLatestTag()
            guard let latest else {
                // Aucune release publiée : ce n'est pas une erreur.
                state = .upToDate
                return
            }
            state = Self.isNewer(latest, than: Self.currentVersion)
                ? .available(version: latest, url: Self.releasesURL)
                : .upToDate
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func fetchLatestTag() async throws -> String? {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }

        // 404 = le dépôt n'a encore aucune release. Rien à signaler.
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else {
            throw UpdateError.badResponse(http.statusCode)
        }

        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease else { return nil }
        return release.tagName
    }

    private struct Release: Decodable {
        var tagName: String
        var draft: Bool = false
        var prerelease: Bool = false

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease
        }
    }

    enum UpdateError: LocalizedError {
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .badResponse(let code):
                "GitHub a répondu \(code)."
            }
        }
    }

    /// Comparaison composante par composante, en tolérant le `v` de tête et un
    /// nombre de composantes différent (`1.2` contre `1.2.0`).
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = components(of: candidate)
        let right = components(of: current)

        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(of version: String) -> [Int] {
        version
            .trimmingCharacters(in: .whitespaces)
            .drop { $0 == "v" || $0 == "V" }
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}
