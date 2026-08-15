import SwiftUI

/// L'assistant de configuration, en écrans successifs.
///
/// Un écran = une chose à comprendre et un bouton. Aucun terminal : pendant les
/// attentes on annonce l'étape en cours et on fait patienter. Le journal brut
/// ne réapparaît qu'à la demande, derrière « Voir le détail », et seulement
/// quand quelque chose a échoué.
struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var step: Step = .welcome
    @State private var failure: String?
    @State private var isShowingLog = false

    enum Step: Int, CaseIterable {
        case welcome, tools, resources, kennel, working, done

        /// Position dans le chapelet de pattes.
        ///
        /// `working` n'a pas de pastille à lui : c'est l'attente de l'étape
        /// « niche ». `done` non plus — c'est l'arrivée, pas une étape ; elle
        /// sort du compte, ce qui allume toutes les pattes.
        var progressIndex: Int {
            switch self {
            case .welcome: 0
            case .tools: 1
            case .resources: 2
            case .kennel, .working: 3
            case .done: Step.progressCount
            }
        }

        static let progressCount = 4
    }

    var body: some View {
        VStack(spacing: 0) {
            PawProgress(current: step.progressIndex, total: Step.progressCount)
                .padding(.top, 22)
                .padding(.bottom, 6)

            Group {
                if let failure {
                    failureScreen(failure)
                } else {
                    screen
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if failure == nil { footer }
        }
        .frame(width: 560, height: 580)
        .background(.background)
        .task { await state.refreshTools() }
    }

    // MARK: - Écrans

    @ViewBuilder
    private var screen: some View {
        switch step {
        case .welcome: welcomeScreen
        case .tools: toolsScreen
        case .resources: resourcesScreen
        case .kennel: kennelScreen
        case .working: workingScreen
        case .done: doneScreen
        }
    }

    private var welcomeScreen: some View {
        ScreenLayout(
            title: "Cocker, at your service",
            subtitle: "He fetches Docker, brings it back, and keeps it warm."
        ) {
            VStack(spacing: 18) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 128, height: 128)

                VStack(alignment: .leading, spacing: 10) {
                    Bullet("He installs colima and the docker tools.")
                    Bullet("He stands guard in the menu bar.")
                    Bullet("He sorts your containers by project.")
                    Bullet("No more Docker Desktop.")
                }
            }
        }
    }

    private var toolsScreen: some View {
        ScreenLayout(
            title: "Fetch!",
            subtitle: "Cocker is sniffing out what's already in his bowl."
        ) {
            VStack(spacing: 8) {
                ForEach(state.tools) { tool in
                    ChecklistRow(tool: tool)
                }

                if let brew = state.tools.first(where: { $0.kind == .homebrew }), !brew.isInstalled
                {
                    HomebrewHint()
                        .padding(.top, 8)
                }
            }
        }
    }

    private var resourcesScreen: some View {
        @Bindable var preferences = state.preferences

        return ScreenLayout(
            title: "The food bowl",
            subtitle: "How much of your Mac is he allowed to chew on?"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ResourceControls(resources: $preferences.desiredResources)

                Text(ResourceControls.diskCaveat)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 380)
        }
    }

    private var kennelScreen: some View {
        @Bindable var preferences = state.preferences

        return ScreenLayout(
            title: "The kennel",
            subtitle: "When does he take up his post?"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                LoginItemToggle()

                Toggle("Wake Docker up along with Cocker", isOn: $preferences.startVMAtLaunch)

                Text(
                    "The kennel stays warm after you quit Cocker: `docker` keeps answering in your terminal until you stop it."
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 380)
        }
    }

    private var workingScreen: some View {
        VStack(spacing: 22) {
            Spacer()

            PawTrail()

            VStack(spacing: 8) {
                Text(
                    verbatim: state.runningOperation.map {
                        String(format: localized($0.key, locale), $0.argument ?? "")
                    } ?? localized("Cocker is busy", locale)
                )
                .font(.title3.weight(.semibold))

                RotatingPhrase(phrases: waitingPhrases)
            }

            Text(
                "Building the first kennel means downloading the VM image. A few minutes, no more."
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 340)

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private var doneScreen: some View {
        ScreenLayout(
            title: "Good boy 🦴",
            subtitle: "Cocker is on guard. You can close this window."
        ) {
            VStack(spacing: 14) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(Color.accentColor)

                VStack(spacing: 6) {
                    SummaryRow(
                        label: "Processors",
                        value: String(
                            format: localized("%d cores", locale), state.vm.resources.cpus))
                    SummaryRow(label: "Memory", value: "\(Int(state.vm.resources.memoryGiB)) GiB")
                    SummaryRow(label: "Disk", value: "\(state.vm.resources.diskGiB) GiB")
                }
                .frame(maxWidth: 280)

                Text("`docker` now answers in your terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// L'échec. Le titre plaisante, la cause est recopiée telle quelle : une
    /// panne déguisée en blague coûte cher au moment de la réparer.
    private func failureScreen(_ message: String) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "tennisball")
                    .font(.system(size: 42))
                    .foregroundStyle(.orange)

                Text(key: DogTalk.Label.lostBall)
                    .font(.title2.weight(.semibold))

                Text(message)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 420)
                    .padding(12)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

                if isShowingLog {
                    LogConsole(lines: state.log, emptyMessage: "Nothing in the log.")
                        .frame(height: 150)
                        .frame(maxWidth: 440)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)

            Divider()

            HStack {
                Button(isShowingLog ? "Hide the detail" : "Show the detail") {
                    withAnimation { isShowingLog.toggle() }
                }

                Spacer()

                Button("Skip this step") {
                    failure = nil
                    skip()
                }

                Button("Throw the ball again") {
                    failure = nil
                    Task { await advance() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isBusy)
            }
            .padding(20)
        }
    }

    // MARK: - Pied

    private var footer: some View {
        HStack {
            if canGoBack {
                Button("Back") { step = previousStep }
                    .controlSize(.large)
                    .disabled(state.isBusy)
            }

            Spacer()

            if state.isBusy, step != .working {
                ProgressView().controlSize(.small)
            }

            Button(primaryTitle) {
                Task { await advance() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(state.isBusy || step == .working)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private var canGoBack: Bool {
        switch step {
        case .tools, .resources, .kennel: true
        default: false
        }
    }

    private var previousStep: Step {
        Step(rawValue: max(0, step.rawValue - 1)) ?? .welcome
    }

    private var primaryTitle: LocalizedStringKey {
        switch step {
        case .welcome:
            "Come on, then!"
        case .tools:
            state.hasToolWork ? "Go fetch!" : "Nothing to fetch, carry on"
        case .resources:
            "Noted"
        case .kennel:
            state.vm.state.isUsable
                ? "He's already up, finish"
                : (state.vm.state == .notCreated ? "Build the kennel" : "Wake Cocker up")
        case .working:
            "Hold on…"
        case .done:
            "Finish"
        }
    }

    private var waitingPhrases: [String] {
        state.vm.state == .notCreated || state.vm.state == .starting
            ? DogTalk.Waiting.creating
            : DogTalk.Waiting.starting
    }

    // MARK: - Enchaînement

    private func advance() async {
        switch step {
        case .welcome:
            step = .tools

        case .tools:
            guard state.hasToolWork else {
                step = .resources
                return
            }
            await run { await state.installAllMissing() }
            if failure == nil { step = .resources }

        case .resources:
            step = .kennel

        case .kennel:
            guard !state.vm.state.isUsable else {
                finish()
                return
            }
            let previous = step
            step = .working
            await run { await state.startVM() }
            step = failure == nil ? .done : previous

        case .working:
            break

        case .done:
            finish()
        }
    }

    /// Laisse l'utilisateur avancer malgré un échec : il saura peut-être le
    /// réparer lui-même, et le bloquer ici ne l'aiderait pas.
    private func skip() {
        switch step {
        case .tools: step = .resources
        case .kennel: step = .done
        default: break
        }
    }

    private func run(_ body: () async -> Void) async {
        failure = nil
        await body()
        if let error = state.lastError {
            failure = error
            state.dismissError()
        }
    }

    private func finish() {
        state.preferences.onboardingCompleted = true
        dismiss()
    }
}

// MARK: - Chrome des écrans

/// Le gabarit commun : un titre, une phrase, un contenu centré.
private struct ScreenLayout<Content: View>: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 10)

            // Un ressort de part et d'autre : le contenu se centre dans la
            // place restante au lieu de laisser un trou sous lui.
            Spacer(minLength: 0)

            content
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }
}

/// Le chapelet de pattes qui dit où on en est.
private struct PawProgress: View {
    var current: Int
    var total: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<total, id: \.self) { index in
                Image(systemName: "pawprint.fill")
                    .font(.system(size: index == current ? 15 : 12))
                    .foregroundStyle(color(for: index))
                    // Une patte sur deux part de l'autre côté : ça fait une
                    // trace de marche plutôt qu'un alignement de points.
                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? -12 : 12))
                    .animation(.snappy, value: current)
            }
        }
    }

    private func color(for index: Int) -> Color {
        // Parcours terminé : tout s'allume franchement, plus rien n'est « en
        // cours ».
        if current >= total { return .accentColor }
        if index == current { return .accentColor }
        return index < current ? .accentColor.opacity(0.45) : .secondary.opacity(0.25)
    }
}

/// Une phrase qui en remplace une autre, toutes les quelques secondes.
private struct RotatingPhrase: View {
    var phrases: [String]
    @State private var index = 0

    var body: some View {
        Text(phrases.isEmpty ? "" : phrases[index % phrases.count])
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(height: 20)
            .id(index)
            .transition(.opacity)
            .task(id: phrases.count) {
                guard phrases.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3.5))
                    withAnimation(.easeInOut(duration: 0.4)) { index += 1 }
                }
            }
    }
}

/// Trois pattes qui s'allument l'une après l'autre : un chien qui trottine.
private struct PawTrail: View {
    @State private var step = 0

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 26))
                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? -14 : 14))
                    .foregroundStyle(Color.accentColor)
                    .opacity(index == step ? 1 : 0.2)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(420))
                withAnimation(.easeInOut(duration: 0.3)) { step = (step + 1) % 3 }
            }
        }
    }
}

// MARK: - Petites pièces

private struct Bullet: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        // `Label` plutôt qu'un `HStack` aligné à la main : sur une image SF
        // Symbol, la ligne de base n'est pas celle du glyphe, et aucun
        // `alignment:` ne rattrape ça proprement. `Label` sait poser l'icône
        // sur la ligne du texte, et garde l'alinéa si la phrase revient à la
        // ligne.
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "pawprint.fill")
                .foregroundStyle(Color.accentColor)
        }
        .labelStyle(.titleAndIcon)
        .font(.callout)
        .imageScale(.small)
    }
}

private struct SummaryRow: View {
    var label: LocalizedStringKey
    var value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.callout)
    }
}

/// Une ligne de la liste des outils. Pas de bouton par ligne : l'écran n'a
/// qu'une seule action, en bas.
private struct ChecklistRow: View {
    var tool: Tool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: tool.kind.displayName)
                    .font(.callout.weight(.medium))
                Text(key: detail)
                    .font(.caption)
                    .foregroundStyle(tool.needsLinking ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(key: status)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: 400)
    }

    private var symbol: String {
        if tool.needsLinking { return "exclamationmark.triangle.fill" }
        return tool.isInstalled ? "checkmark.circle.fill" : "circle.dashed"
    }

    private var color: Color {
        if tool.needsLinking { return .orange }
        return tool.isInstalled ? .green : .secondary
    }

    private var detail: String {
        if tool.needsLinking { return "Installed, but docker cannot find it." }
        return tool.version ?? tool.kind.summary
    }

    private var status: String {
        if tool.needsLinking { return "to put away" }
        if tool.isInstalled { return "in the bowl" }
        return tool.kind.isRequired ? "to fetch" : "optional"
    }
}

/// Homebrew s'installe dans un terminal, avec le mot de passe admin.
private struct HomebrewHint: View {
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                "Homebrew is the one thing Cocker cannot fetch: installing it asks for your administrator password in a terminal."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(Toolchain.homebrewInstallCommand)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

                Button(didCopy ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        Toolchain.homebrewInstallCommand, forType: .string)
                    didCopy = true
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: 400)
    }
}
