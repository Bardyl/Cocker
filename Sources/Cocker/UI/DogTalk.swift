import Foundation

/// Tout le vocabulaire canin de l'app, réuni ici.
///
/// Rassemblé en un seul endroit pour deux raisons : le ton reste cohérent, et
/// on peut le faire évoluer sans fouiller les vues. Règle qu'on s'impose :
/// le chien décore les titres et les attentes, jamais la cause d'une panne.
/// Un message d'erreur reste affiché mot pour mot sous le titre.
enum DogTalk {

    /// Phrases qui tournent pendant une attente. Elles ne décrivent rien de
    /// précis — c'est assumé : leur rôle est de faire patienter, l'étape en
    /// cours est annoncée juste au-dessus.
    enum Waiting {
        static let installing = [
            "Il renifle les formules Homebrew…",
            "Il rapporte colima…",
            "Il secoue la poussière…",
            "Il mâchouille les paquets…",
            "Il lâche la balle, la reprend aussitôt…",
            "Il fait tomber quelque chose, on ne dira rien…",
        ]

        static let creating = [
            "Il creuse un trou pour la niche…",
            "Il tourne trois fois avant de se coucher…",
            "Il mâchouille l'image disque…",
            "Il tasse bien la paille…",
            "Il vérifie qu'il n'y a pas de chat dans le coin…",
            "Il enterre un os pour plus tard…",
        ]

        static let starting = [
            "Il se réveille…",
            "Il s'étire longuement…",
            "Il agite la queue…",
            "Il vient en trottinant…",
        ]

        static let stopping = [
            "Il rentre au panier…",
            "Il fait ses trois tours…",
            "Il pose la tête sur ses pattes…",
        ]

        static let cleaning = [
            "Il déterre les vieux os…",
            "Il fait le tri dans ses jouets…",
            "Il secoue le panier…",
        ]
    }

    /// Titres et étiquettes courtes.
    enum Label {
        static let idle = "Cocker fait la sieste"
        static let running = "Cocker monte la garde"
        static let emptyKennel = "La niche est vide"
        static let notTrained = "Cocker n'est pas encore dressé"
        static let lostBall = "Il a perdu la balle"
    }

    /// Nom d'une opération en cours, affiché dans le panneau.
    enum Operation {
        static let start = "Cocker se réveille"
        static let stop = "Cocker rentre au panier"
        static let resize = "Cocker refait sa niche"
        static let cleaning = "Cocker fait le ménage"

        static func install(_ tool: String) -> String { "Cocker va chercher \(tool)" }
        static func link(_ tool: String) -> String { "Cocker range \(tool)" }
        static let installAll = "Cocker fait sa tournée"
        static func container(_ action: String, _ name: String) -> String { "\(action) \(name)" }
    }
}
