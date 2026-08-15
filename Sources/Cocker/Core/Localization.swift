import SwiftUI

/// Traduction de clés calculées à l'exécution.
///
/// Piège de SwiftUI : `Text("literal")` passe par `LocalizedStringKey` et se
/// traduit, mais `Text(uneVariable)` prend la surcharge `StringProtocol` et
/// affiche la chaîne telle quelle. Les libellés qui viennent des modèles —
/// l'état d'un conteneur, le nom d'un outil — sont des variables : il faut
/// dire explicitement que ce sont des clés.
extension Text {
    init(key: String) {
        self.init(LocalizedStringKey(key))
    }
}

/// Traduit une clé dans une locale imposée.
///
/// Sert aux quelques endroits où le texte est composé avant d'être affiché et
/// ne peut donc pas passer par `Text`. On vise explicitement le `.lproj`
/// demandé plutôt que de s'en remettre à `AppleLanguages`, que Foundation met
/// en cache et qui ne suivrait pas un changement de langue à chaud.
func localized(_ key: String, _ locale: Locale) -> String {
    let fallback = Bundle.main.localizedString(forKey: key, value: key, table: nil)

    guard let code = locale.language.languageCode?.identifier,
          let path = Bundle.main.path(forResource: code, ofType: "lproj"),
          let bundle = Bundle(path: path)
    else { return fallback }

    return bundle.localizedString(forKey: key, value: fallback, table: nil)
}
