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
                display: "\(Int(resources.memoryGiB)) GiB"
            )

            slider(
                label: "Disk",
                value: Binding(
                    get: { Double(resources.diskGiB) },
                    set: { resources.diskGiB = Int(($0 / 10).rounded()) * 10 }
                ),
                range: 20...400,
                display: "\(resources.diskGiB) GiB"
            )
        }
    }

    private func slider(
        label: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: LocalizedStringKey
    ) -> some View {
        LabeledContent(label) {
            HStack(spacing: 10) {
                Slider(value: value, in: range)
                Text(display)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .trailing)
            }
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
