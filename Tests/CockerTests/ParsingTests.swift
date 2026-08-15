import Testing
@testable import Cocker

/// Ces tests portent sur les seuls endroits où Cocker dépend du format de
/// sortie d'un outil externe. C'est là que ça a déjà cassé deux fois, et c'est
/// là que ça cassera encore quand docker ou colima changeront d'avis.

// MARK: - docker ps

@Suite("Conteneurs docker")
struct ContainerParsingTests {

    /// Une ligne réelle de `docker ps --format '{{json .}}'`, docker 29.
    let composeLine = """
    {"Command":"\\"/docker-entrypoint.…\\"","CreatedAt":"2026-08-15 15:45:12 -0400 EDT",\
    "ID":"9f1c2","Image":"nginx:alpine","Labels":"com.docker.compose.project=frosty,\
    com.docker.compose.service=web,maintainer=NGINX","Names":"frosty-web-1",\
    "Ports":"0.0.0.0:5173->80/tcp, [::]:5173->80/tcp","State":"running",\
    "Status":"Up 3 minutes"}
    """

    @Test("Les champs essentiels sont lus")
    func readsCoreFields() {
        let containers = Docker.parseContainers(from: composeLine)
        #expect(containers.count == 1)

        let container = try! #require(containers.first)
        #expect(container.id == "9f1c2")
        #expect(container.name == "frosty-web-1")
        #expect(container.image == "nginx:alpine")
        #expect(container.state == .running)
        #expect(container.status == "Up 3 minutes")
    }

    @Test("Le projet et le service Compose sont extraits des labels")
    func readsComposeLabels() {
        let container = Docker.parseContainers(from: composeLine).first
        #expect(container?.project == "frosty")
        #expect(container?.service == "web")
        // Dans un projet, c'est le nom du service qui s'affiche.
        #expect(container?.displayName == "web")
    }

    /// docker annonce deux fois le même port, en IPv4 puis en IPv6.
    @Test("Les ports IPv4 et IPv6 se dédoublonnent")
    func deduplicatesPorts() {
        let container = Docker.parseContainers(from: composeLine).first
        #expect(container?.ports.count == 1)
        #expect(container?.ports.first?.hostPort == 5173)
        #expect(container?.ports.first?.containerPort == 80)
        #expect(container?.ports.first?.protocolName == "tcp")
    }

    @Test("Un conteneur sans port publié n'en déclare aucun")
    func handlesNoPorts() {
        let line = """
        {"ID":"abc","Image":"redis:alpine","Names":"frosty-cache-1","Ports":"",\
        "State":"running","Status":"Up 1 minute","Labels":""}
        """
        #expect(Docker.parseContainers(from: line).first?.ports.isEmpty == true)
    }

    /// Les ports internes n'ont pas de flèche : ils ne doivent pas être
    /// confondus avec une publication sur l'hôte.
    @Test("Les ports non publiés sont ignorés")
    func ignoresUnpublishedPorts() {
        let line = """
        {"ID":"abc","Image":"axllent/mailpit","Names":"fantomas-mail-1",\
        "Ports":"1025/tcp, 1110/tcp, 0.0.0.0:8025->8025/tcp","State":"running",\
        "Status":"Up 2 minutes","Labels":""}
        """
        let ports = Docker.parseContainers(from: line).first?.ports
        #expect(ports?.count == 1)
        #expect(ports?.first?.hostPort == 8025)
    }

    @Test("Un état inconnu ne fait pas perdre le conteneur")
    func toleratesUnknownState() {
        let line = """
        {"ID":"abc","Image":"alpine","Names":"x","Ports":"","State":"hibernating",\
        "Status":"?","Labels":""}
        """
        #expect(Docker.parseContainers(from: line).first?.state == .unknown)
    }

    @Test("Une ligne illisible est écartée sans emporter les autres")
    func skipsGarbageLines() {
        let output = """
        pas du json
        {"ID":"abc","Image":"alpine","Names":"x","Ports":"","State":"running","Status":"Up","Labels":""}

        """
        #expect(Docker.parseContainers(from: output).count == 1)
    }

    @Test("Un conteneur sans identifiant est rejeté")
    func rejectsMissingID() {
        let line = #"{"Image":"alpine","Names":"x","State":"running"}"#
        #expect(Docker.parseContainers(from: line).isEmpty)
    }
}

// MARK: - Regroupement

@Suite("Regroupement par projet")
struct GroupingTests {

    private func container(_ id: String, project: String?, running: Bool = true) -> Container {
        Container(
            id: id,
            name: id,
            image: "alpine",
            state: running ? .running : .exited,
            status: "",
            ports: [],
            project: project,
            service: id
        )
    }

    @Test("Les conteneurs isolés atterrissent dans le fourre-tout, en dernier")
    func loneContainersGoLast() {
        let groups = Docker.group([
            container("solo", project: nil),
            container("web", project: "westroad"),
            container("api", project: "fantomas"),
        ])

        #expect(groups.map(\.name) == ["fantomas", "westroad", ContainerGroup.looseName])
        #expect(groups.last?.isLoose == true)
    }

    @Test("Le compteur ne retient que ce qui tourne")
    func countsRunningOnly() {
        let groups = Docker.group([
            container("api", project: "fantomas"),
            container("worker", project: "fantomas", running: false),
        ])

        let fantomas = try! #require(groups.first)
        #expect(fantomas.containers.count == 2)
        #expect(fantomas.runningCount == 1)
        #expect(fantomas.isRunning)
    }

    @Test("Un projet entièrement arrêté n'est pas dit en marche")
    func detectsFullyStoppedProject() {
        let groups = Docker.group([container("worker", project: "pensy", running: false)])
        #expect(groups.first?.isRunning == false)
    }
}

// MARK: - colima

@Suite("État colima")
struct ColimaParsingTests {

    /// `colima status --json` dit `cpu` au singulier et `display_name`.
    @Test("La sortie de `colima status` est lue")
    func readsStatusOutput() {
        let output = """
        {"display_name":"colima","driver":"macOS Virtualization.Framework","arch":"aarch64",\
        "runtime":"docker","mount_type":"virtiofs",\
        "docker_socket":"unix:///Users/x/.colima/default/docker.sock",\
        "kubernetes":false,"cpu":6,"memory":12884901888,"disk":64424509440}
        """
        let status = try! #require(Colima.parseRunningStatus(from: output))

        #expect(status.state == .running)
        #expect(status.resources.cpus == 6)
        #expect(status.resources.memoryGiB == 12)
        #expect(status.resources.diskGiB == 60)
        #expect(status.runtime == "docker")
        #expect(status.architecture == "aarch64")
    }

    /// `colima list --json` dit `cpus` au pluriel et porte un `status`.
    /// C'est cette divergence qui affichait 4 cœurs au lieu de 6.
    @Test("La sortie de `colima list` est lue malgré des clés différentes")
    func readsListOutput() {
        let output = """
        {"name":"default","status":"Running","arch":"aarch64","cpus":6,\
        "memory":12884901888,"disk":64424509440,"runtime":"docker"}
        """
        let status = try! #require(Colima.parseList(from: output))

        #expect(status.state == .running)
        #expect(status.resources.cpus == 6)
        #expect(status.resources.memoryGiB == 12)
    }

    @Test("Un profil arrêté est reconnu comme tel")
    func readsStoppedProfile() {
        let output = """
        {"name":"default","status":"Stopped","arch":"aarch64","cpus":4,\
        "memory":8589934592,"disk":64424509440,"runtime":"docker"}
        """
        #expect(Colima.parseList(from: output)?.state == .stopped)
    }

    @Test("Un autre profil que le nôtre est ignoré")
    func ignoresOtherProfiles() {
        let output = #"{"name":"kubernetes","status":"Running","cpus":2}"#
        #expect(Colima.parseList(from: output) == nil)
    }

    @Test("Une sortie vide ne produit pas d'état")
    func handlesEmptyOutput() {
        #expect(Colima.parseList(from: "") == nil)
        #expect(Colima.parseRunningStatus(from: "") == nil)
    }

    /// Les anciennes versions annonçaient des GiB, les récentes des octets.
    @Test("Les tailles en GiB comme en octets sont comprises")
    func acceptsBothMemoryUnits() {
        let asBytes = #"{"name":"default","status":"Running","cpus":2,"memory":8589934592}"#
        let asGiB = #"{"name":"default","status":"Running","cpus":2,"memory":8}"#

        #expect(Colima.parseList(from: asBytes)?.resources.memoryGiB == 8)
        #expect(Colima.parseList(from: asGiB)?.resources.memoryGiB == 8)
    }
}

// MARK: - Tailles

@Suite("Tailles docker")
struct ByteSizeTests {

    @Test("Les unités usuelles sont converties", arguments: [
        ("0B", Int64(0)),
        ("512B", 512),
        ("1.5kB", 1_536),
        ("890MB", 933_232_640),
        ("1.23GB", 1_320_702_444),
    ])
    func parsesUnits(text: String, expected: Int64) {
        // Tolérance d'un octet : la conversion passe par un flottant.
        #expect(abs(ByteSize.parse(text) - expected) <= 1)
    }

    /// `docker system df` accole un pourcentage à la colonne récupérable.
    @Test("Le pourcentage entre parenthèses est ignoré")
    func ignoresTrailingPercentage() {
        #expect(ByteSize.parse("1.2GB (50%)") == ByteSize.parse("1.2GB"))
    }

    @Test("Une valeur illisible vaut zéro plutôt que de faire échouer la lecture")
    func fallsBackToZero() {
        #expect(ByteSize.parse("") == 0)
        #expect(ByteSize.parse("N/A") == 0)
    }

    @Test("Le tableau de `docker system df` est ventilé par type")
    func parsesDiskUsageRows() {
        let output = """
        {"Type":"Images","TotalCount":"5","Active":"5","Size":"687.8MB","Reclaimable":"0B (0%)"}
        {"Type":"Containers","TotalCount":"12","Active":"11","Size":"1.09MB","Reclaimable":"4.096kB (0%)"}
        {"Type":"Local Volumes","TotalCount":"2","Active":"2","Size":"95.22MB","Reclaimable":"0B (0%)"}
        {"Type":"Build Cache","TotalCount":"0","Active":"0","Size":"0B","Reclaimable":"0B"}
        """
        let usage = Docker.parseDiskUsage(from: output)

        #expect(usage.imagesBytes == ByteSize.parse("687.8MB"))
        #expect(usage.containersBytes == ByteSize.parse("1.09MB"))
        #expect(usage.volumesBytes == ByteSize.parse("95.22MB"))
        #expect(usage.totalBytes > 0)
    }
}

// MARK: - Bruit pendant les transitions

@Suite("Démon injoignable")
struct DaemonReadinessTests {

    /// Le message qui s'affichait au réveil : docker retombait sur la socket
    /// système faute de trouver celle de colima.
    @Test("Une socket absente n'est pas signalée comme une panne")
    func recognisesMissingSocket() {
        let message = "docker ps : failed to connect to the docker API at "
            + "unix:///var/run/docker.sock; check if the path is correct and if the "
            + "daemon is running: dial unix /var/run/docker.sock: connect: "
            + "no such file or directory"
        #expect(Docker.isDaemonUnreachable(message))
    }

    @Test("Le message classique du CLI est reconnu")
    func recognisesClassicMessage() {
        #expect(Docker.isDaemonUnreachable(
            "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. "
            + "Is the docker daemon running?"
        ))
    }

    /// Tout ce qui n'est pas un problème de connexion doit continuer d'être
    /// montré : masquer une vraie erreur serait pire que le faux positif.
    @Test("Une vraie erreur reste une erreur", arguments: [
        "Error response from daemon: no such container: frosty-web-1",
        "permission denied while trying to connect",
        "invalid reference format",
    ])
    func keepsRealErrors(message: String) {
        #expect(!Docker.isDaemonUnreachable(message))
    }
}
