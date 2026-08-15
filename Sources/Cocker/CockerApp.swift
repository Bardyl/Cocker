import SwiftUI

enum WindowID {
    static let onboarding = "onboarding"
    static let logs = "logs"
    static let about = "about"
}

@main
@MainActor
struct CockerApp: App {

    @State private var state: AppState

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environment(state)
                .environment(\.locale, state.preferences.language.locale)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)

        Window("Cocker Setup", id: WindowID.onboarding) {
            OnboardingView()
                .environment(state)
                .environment(\.locale, state.preferences.language.locale)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Scène `Settings` et non `Window` : c'est elle qui donne la barre
        // d'onglets native de macOS, celle des Réglages Système.
        Settings {
            SettingsView()
                .environment(state)
                .environment(\.locale, state.preferences.language.locale)
        }

        Window("About Cocker", id: WindowID.about) {
            AboutView()
                .environment(state)
                .environment(\.locale, state.preferences.language.locale)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        WindowGroup("Logs", id: WindowID.logs, for: String.self) { $containerID in
            LogsView(containerID: containerID)
                .environment(state)
                .environment(\.locale, state.preferences.language.locale)
        }
        .defaultSize(width: 720, height: 460)
    }

    init() {
        // La boucle de sondage doit tourner même si le panneau n'a jamais été
        // ouvert : c'est elle qui démarre la VM au login.
        let state = AppState()
        _state = State(initialValue: state)
        state.start()
    }
}

/// L'icône dans la barre de menus. Elle porte à elle seule l'état de Docker.
struct MenuBarLabel: View {
    var state: AppState

    @Environment(\.openWindow) private var openWindow
    @State private var hasPresentedOnboarding = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbolName)
                .symbolRenderingMode(.hierarchical)

            if state.vm.state.isUsable, state.runningContainerCount > 0 {
                Text(String(state.runningContainerCount))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
        }
        .task { await presentOnboardingIfNeeded() }
    }

    /// Au premier lancement, une icône d'alerte muette n'apprend rien : mieux
    /// vaut ouvrir l'assistant. Ensuite, on ne s'impose plus.
    private func presentOnboardingIfNeeded() async {
        guard !hasPresentedOnboarding, !state.preferences.onboardingCompleted else { return }
        hasPresentedOnboarding = true

        // Laisse le premier sondage aboutir, sinon on décide sur un état
        // « inconnu » et l'assistant s'ouvre pour rien.
        while state.vm.state == .unknown, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
        }

        guard state.needsOnboarding else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: WindowID.onboarding)
    }

    /// La patte pleine quand Cocker monte la garde, en contour quand il dort.
    private var symbolName: String {
        switch state.vm.state {
        case .running: "pawprint.fill"
        case .starting, .stopping: "pawprint.circle"
        case .missing, .notCreated: "exclamationmark.triangle"
        case .stopped, .unknown: "pawprint"
        }
    }
}
