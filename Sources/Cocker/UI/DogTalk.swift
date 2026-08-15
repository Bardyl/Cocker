import Foundation

/// Tout le vocabulaire canin de l'app, réuni ici.
///
/// Rassemblé en un seul endroit pour deux raisons : le ton reste cohérent, et
/// on peut le faire évoluer sans fouiller les vues. Règle qu'on s'impose :
/// le chien décore les titres et les attentes, jamais la cause d'une panne.
/// Un message d'erreur reste affiché mot pour mot sous le titre.
///
/// Ce sont des clés de traduction, pas du texte : l'anglais fait office de clé
/// et le français vit dans `fr.lproj`. Le ton ne se traduit pas mot à mot, il
/// se réécrit — c'est pour ça que les deux versions ne se correspondent pas
/// toujours littéralement.
enum DogTalk {

    /// Phrases qui tournent pendant une attente. Elles ne décrivent rien de
    /// précis — c'est assumé : leur rôle est de faire patienter, l'étape en
    /// cours est annoncée juste au-dessus.
    enum Waiting {
        static let installing = [
            "He's sniffing out the Homebrew formulas…",
            "He's fetching colima…",
            "He's shaking off the dust…",
            "He's chewing through the packages…",
            "He drops the ball, picks it straight back up…",
            "He knocked something over. We'll say nothing…",
        ]

        static let creating = [
            "He's digging a hole for the kennel…",
            "He's turning around three times before lying down…",
            "He's gnawing on the disk image…",
            "He's patting down the straw…",
            "He's checking there's no cat around…",
            "He's burying a bone for later…",
        ]

        static let starting = [
            "He's waking up…",
            "He's having a long stretch…",
            "He's wagging his tail…",
            "He's trotting over…",
        ]

        static let stopping = [
            "He's heading back to his basket…",
            "He's doing his three turns…",
            "He's resting his head on his paws…",
        ]

        static let cleaning = [
            "He's digging up the old bones…",
            "He's sorting through his toys…",
            "He's shaking out the basket…",
        ]
    }

    /// Titres et étiquettes courtes.
    enum Label {
        static let idle = "Cocker is napping"
        static let running = "Cocker is on guard"
        static let emptyKennel = "The kennel is empty"
        static let notTrained = "Cocker isn't trained yet"
        static let lostBall = "He lost the ball"
    }

    /// Nom d'une opération en cours, affiché dans le panneau.
    ///
    /// Renvoie une clé : c'est la vue qui la traduira, au moment de l'afficher
    /// et dans la langue du moment.
    enum Operation {
        static let start = "Cocker is waking up"
        static let stop = "Cocker is going back to his basket"
        static let resize = "Cocker is rebuilding his kennel"
        static let cleaning = "Cocker is tidying up"
        static let installAll = "Cocker is doing his rounds"

        /// Clés à format : le nom de l'outil est un argument, pas un morceau
        /// de la clé — sinon chaque outil produirait une traduction distincte.
        static let installOne = "Cocker is fetching %@"
        static let linkOne = "Cocker is putting away %@"
    }
}
