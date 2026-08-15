import Foundation
import ServiceManagement

/// Lancement de Cocker à l'ouverture de session.
///
/// `SMAppService.mainApp` inscrit l'app elle-même ; c'est macOS qui la relance,
/// et l'utilisateur garde la main depuis Réglages Système › Ouverture.
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// `true` quand l'utilisateur a explicitement désactivé Cocker dans les
    /// Réglages Système : réinscrire échouerait silencieusement.
    static var isBlockedByUser: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard SMAppService.mainApp.status == .enabled else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
