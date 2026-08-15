import Foundation

/// La langue de l'interface.
///
/// Deux traductions seulement, et « Système » par défaut : une machine
/// configurée en allemand retombera sur l'anglais, qui est la langue de
/// développement déclarée dans l'Info.plist.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case french

    var id: String { rawValue }

    /// Clé d'affichage. Les noms de langue sont donnés dans leur propre
    /// langue — c'est ainsi qu'on choisit une langue qu'on ne lit pas encore —
    /// donc eux seuls ne se traduisent pas.
    var label: String {
        switch self {
        case .system: "Automatic"
        case .english: "English"
        case .french: "Français"
        }
    }

    var locale: Locale {
        switch self {
        case .system: Locale.autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .french: Locale(identifier: "fr")
        }
    }

    /// Les codes à écrire dans `AppleLanguages`.
    ///
    /// `Locale` suffit à SwiftUI pour choisir la traduction affichée, mais pas
    /// aux chaînes résolues hors vue : `AppleLanguages` couvre le reste.
    var preferredLanguages: [String]? {
        switch self {
        case .system: nil
        case .english: ["en"]
        case .french: ["fr"]
        }
    }
}
