import AppKit

/// Keeps the app from being taken offline by a stray click while it is serving
/// Buddy remote approvals. Local-only users retain the existing one-click quit.
@MainActor
final class ApplicationQuitController {
    struct Confirmation {
        let title: String
        let message: String
        let confirmButtonTitle: String
        let cancelButtonTitle: String

        static let remoteAccess = Confirmation(
            title: "Quit CodeIsland?",
            message: "Buddy remote access and remote approvals will stop until CodeIsland is opened again on this Mac.",
            confirmButtonTitle: "Quit CodeIsland",
            cancelButtonTitle: "Cancel"
        )
    }

    static let shared = ApplicationQuitController(
        isRemoteAccessEnabled: {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: SettingsKey.remoteApprovalsEnabled) != nil else {
                return SettingsDefaults.remoteApprovalsEnabled
            }
            return defaults.bool(forKey: SettingsKey.remoteApprovalsEnabled)
        },
        confirm: { confirmation in
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = confirmation.title
            alert.informativeText = confirmation.message

            let quitButton = alert.addButton(withTitle: confirmation.confirmButtonTitle)
            quitButton.hasDestructiveAction = true
            let cancelButton = alert.addButton(withTitle: confirmation.cancelButtonTitle)
            cancelButton.keyEquivalent = "\u{1b}"

            return alert.runModal() == .alertFirstButtonReturn
        },
        terminate: {
            NSApp.terminate(nil)
        }
    )

    private let isRemoteAccessEnabled: () -> Bool
    private let confirm: (Confirmation) -> Bool
    private let terminate: () -> Void

    init(
        isRemoteAccessEnabled: @escaping () -> Bool,
        confirm: @escaping (Confirmation) -> Bool,
        terminate: @escaping () -> Void
    ) {
        self.isRemoteAccessEnabled = isRemoteAccessEnabled
        self.confirm = confirm
        self.terminate = terminate
    }

    func requestQuit() {
        terminate()
    }

    /// Called from the application delegate so native app-menu, Dock, and
    /// keyboard quit commands receive the same remote-access protection.
    func shouldTerminate() -> Bool {
        !isRemoteAccessEnabled() || confirm(.remoteAccess)
    }
}
