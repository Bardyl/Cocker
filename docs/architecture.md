# Architecture — Cocker

> Cette page est lue par les agents autant que par toi. Décris les
> décisions structurantes et leurs raisons, pas ce que le code dit déjà.

## Le principe

Cocker ne parle jamais à l'API Docker ni à lima directement : il appelle les
CLI (`brew`, `colima`, `docker`) et lit leur sortie JSON. C'est plus lent
qu'une socket, mais ça suit gratuitement les évolutions de colima et de docker,
et ça garde le code lisible. Une app qui gère un environnement de dev n'a pas
besoin de millisecondes.

## Pourquoi SwiftPM et pas un projet Xcode

Tout est en texte : `Package.swift`, les sources, `Resources/Info.plist`,
`Scripts/bundle.sh`. Aucun `.pbxproj` à relire dans un diff. SwiftPM ne sait
produire qu'un binaire, donc `Scripts/bundle.sh` assemble le `.app` à la main —
c'est une vingtaine de lignes et ça reste compréhensible.

La signature ad hoc du script n'est pas cosmétique : sans elle, `SMAppService`
refuse d'inscrire l'app au démarrage, et macOS redemande l'autorisation à
chaque recompilation.

## Le PATH

Une app lancée par le Finder n'hérite pas du `PATH` du shell. Homebrew, colima
et docker sont donc invisibles par défaut. `Shell.environment()` reconstruit un
`PATH` explicite (`/opt/homebrew/bin` en tête) ; toute exécution passe par là.
C'est aussi pour ça que `Shell.which(_:)` fouille une liste de dossiers plutôt
que d'appeler `which`.

## La socket Docker

Après `colima start --activate`, le contexte docker actif pointe vers la VM.
Mais rien ne garantit qu'une app GUI lise le même contexte que ton shell : on
force donc `DOCKER_HOST` sur `~/.colima/default/docker.sock` quand ce fichier
existe. Un seul endroit à corriger si le chemin change : `Docker.environment()`.

## Le regroupement par projet

Compose étiquette ses conteneurs avec `com.docker.compose.project` et
`com.docker.compose.service`. C'est la seule source de vérité utilisée pour
grouper ; les conteneurs lancés à la main tombent dans un groupe « Sans
projet », toujours affiché en dernier.

## Les plugins docker

Homebrew installe `docker-compose` et `docker-buildx` dans
`/opt/homebrew/lib/docker/cli-plugins`, un dossier que le CLI docker ne fouille
pas. Résultat classique : `docker compose` répond « unknown command » alors que
le binaire est là. Cocker détecte l'écart (`Tool.needsLinking`) et le répare
par un lien symbolique dans `~/.docker/cli-plugins` — un lien et pas une copie,
pour que `brew upgrade` suffise ensuite.

## Ressources voulues contre ressources appliquées

`Preferences.desiredResources` est ce que l'utilisateur règle ;
`VMStatus.resources` est ce que colima applique vraiment. L'écart entre les
deux est la seule raison d'être du bouton « Appliquer », qui impose un cycle
stop/start — et donc l'arrêt des conteneurs. C'est pour ça que l'interface le
dit avant le clic plutôt qu'après.

Le disque ne peut qu'augmenter : colima refuse de réduire un disque existant.

## Le rythme de sondage

Chaque sondage lance un processus. Coûts mesurés sur une machine Apple Silicon :

| Commande | Coût |
|---|---|
| `colima list --json` | 0,10 s |
| `colima status --json` | 0,37 s |
| `docker ps` | 0,01 s |
| `docker system df` | 0,01 s |
| sondage des outils (5 processus) | 0,40 s |

D'où trois décisions :

**On lit l'état de la VM avec `list`, pas `status`.** Trois fois et demie moins
cher, et `status` échoue quand la VM dort — on payait alors les deux. `list`
porte déjà tout ce que l'interface affiche.

**Les conteneurs sont sondés bien plus souvent que la VM.** À 0,01 s, `docker
ps` peut tourner toutes les 3 secondes sans qu'on le sente ; l'état de la VM ne
change qu'à la demande, donc toutes les 10 s. Panneau fermé, la boucle ralentit
à 15 s, et à 60 s quand la VM est arrêtée — plus rien ne peut alors changer sans
une action délibérée.

**Les outils ne sont pas sondés périodiquement du tout.** Ils ne s'installent
pas seuls : au lancement, après chaque opération, et à l'ouverture de
l'assistant. Le faire à la minute coûtait 0,40 s de processus pour constater
qu'il ne s'était rien passé.

Au repos, panneau fermé, l'app consomme 84 Mo de RSS stables et ne fait
tourner que 0,44 s de processus enfants par minute.

## Ce que Cocker ne fait pas

- Il n'installe pas Homebrew : le script officiel réclame le mot de passe
  administrateur dans un terminal, ce qu'une app sans terminal ne peut pas
  offrir honnêtement. L'assistant donne la commande à copier.
- Il ne gère qu'un profil colima (`default`). Plusieurs profils
  compliqueraient l'interface pour un besoin rare.
- Il ne suit pas les logs en flux (`docker logs -f`) : il relit les 300
  dernières lignes toutes les 3 s tant que la fenêtre est ouverte, ce qui évite
  de garder un processus vivant par fenêtre.
