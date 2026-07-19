import SwiftUI

@main
struct CodeIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var l10n = L10n.shared

    var body: some Scene {
        Settings {
            SettingsView(appState: appDelegate.appState)
        }
        .commands {
            CommandMenu("Capture") {
                Button("Remote Coding Tasks") {
                    RemoteTasksWindowController.shared.show(appState: appDelegate.appState)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("New Task") {
                    QuickJotWindowController.shared.show(destination: .task)
                }
                Button("New Note") {
                    QuickJotWindowController.shared.show(destination: .note)
                }
            }
        }
    }
}
