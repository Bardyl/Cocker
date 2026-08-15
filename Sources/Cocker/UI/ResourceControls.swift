import SwiftUI

/// Curseurs de ressources, partagés par l'assistant et les réglages.
///
/// Les curseurs n'ont pas de `step` : macOS dessinerait une graduation par
/// cran, soit quarante traits pour le disque. L'arrondi se fait dans le
/// binding, ce qui donne le même accrochage sans le bruit visuel.
struct ResourceControls: View {
    @Binding var resources: VMResources

    static let diskCaveat = LocalizedStringKey(
        "Disk can only grow: colima refuses to shrink one on an existing VM."
    )

    /// Un `Group` et non un `VStack` : dans un `Form`, chaque `LabeledContent`
    /// devient une vraie ligne et s'aligne sur la colonne de contenu ; ailleurs,
    /// ils s'empilent simplement.
    var body: some View {
        Group {
            slider(
                label: "Processors",
                value: Binding(
                    get: { Double(resources.cpus) },
                    set: { resources.cpus = Int($0.rounded()) }
                ),
                range: 1...Double(Preferences.maxCPUs),
                display: "\(resources.cpus) / \(Preferences.maxCPUs)"
            )

            slider(
                label: "Memory",
                value: Binding(
                    get: { resources.memoryGiB },
                    set: { resources.memoryGiB = $0.rounded() }
                ),
                range: 1...Preferences.maxMemoryGiB,
                display: "\(Int(resources.memoryGiB)) / \(Int(Preferences.maxMemoryGiB)) GiB"
            )

            slider(
                label: "Disk",
                value: Binding(
                    get: { Double(resources.diskGiB) },
                    set: { resources.diskGiB = Int(($0 / 10).rounded()) * 10 }
                ),
                // La borne haute suit l'espace libre du Mac, et la basse la
                // taille déjà allouée : colima refuse de réduire un disque.
                range: Double(
                    Preferences.minimumDiskGiB)...Double(
                        max(Preferences.maxDiskGiB, resources.diskGiB)
                    ),
                display:
                    "\(resources.diskGiB) / \(max(Preferences.maxDiskGiB, resources.diskGiB)) GiB"
            )
        }
    }

    private func slider(
        label: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: LocalizedStringKey
    ) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: value, in: range)
                Text(display)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    // Colonne fixe pour que les trois curseurs aient la même
                    // longueur, mais alignée à gauche : à droite, une valeur
                    // courte comme « 5 / 10 » flottait loin de son curseur.
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 96, alignment: .leading)
            }
        } label: {
            // Colonne de largeur fixe : hors d'un `Form`, `LabeledContent`
            // dimensionne chaque ligne indépendamment, si bien que le curseur
            // démarrait après le libellé et que les trois barres n'avaient pas
            // la même longueur.
            Text(label).frame(width: 92, alignment: .leading)
        }
    }
}

/// Interrupteur « lancer Cocker à l'ouverture de session ».
struct LoginItemToggle: View {
    @State private var isEnabled = LoginItem.isEnabled
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch Cocker at login", isOn: $isEnabled)
                .onChange(of: isEnabled) { _, newValue in
                    do {
                        try LoginItem.setEnabled(newValue)
                        failure = nil
                    } catch {
                        // On resynchronise sur la vérité du système plutôt que
                        // de laisser l'interrupteur mentir.
                        isEnabled = LoginItem.isEnabled
                        failure = error.localizedDescription
                    }
                }

            if LoginItem.isBlockedByUser {
                Button("Allow in System Settings…") {
                    LoginItem.openSystemSettings()
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            if let failure {
                Text(failure)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}
