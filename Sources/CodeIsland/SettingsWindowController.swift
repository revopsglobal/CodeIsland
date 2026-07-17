import AppKit
import SwiftUI

@MainActor
class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var hostingController: NSHostingController<SettingsView>?
    weak var appState: AppState?

    private var closeObserver: NSObjectProtocol?

    private func clearCloseObserver() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
    }

    func show(page: SettingsPage = .general) {
        // Switch to regular activation policy so the window can receive focus
        NSApp.setActivationPolicy(.regular)
        // Use the actual bundle app icon so Dock matches the packaged asset catalog icon.
        NSApp.applicationIconImage = Self.bundleAppIcon()

        if let window = window {
            hostingController?.rootView = SettingsView(appState: appState, initialPage: page)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(appState: appState, initialPage: page)
        let hostingController = NSHostingController(rootView: settingsView)

        let screen = NSScreen.main ?? NSScreen.screens.first
        let screenW = screen?.frame.width ?? 1440
        let screenH = screen?.frame.height ?? 900
        let winW = min(660, screenW * 0.5)
        let winH = min(540, screenH * 0.6)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winW, height: winH),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .visible
        window.title = L10n.shared["settings_title"]
        window.backgroundColor = .windowBackgroundColor
        // Let NSHostingController own the content view and its layout lifecycle.
        // Assigning a bare NSHostingView here can leave its frame at zero on a
        // menu-bar app's first regular window, producing a toolbar with a blank
        // content area and no usable permission controls.
        window.contentViewController = hostingController
        hostingController.view.frame = NSRect(
            origin: .zero,
            size: window.contentLayoutRect.size
        )
        hostingController.view.autoresizingMask = [.width, .height]
        window.setContentSize(NSSize(width: winW, height: winH))
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentMinSize = NSSize(width: min(560, screenW * 0.4), height: min(420, screenH * 0.4))
        window.toolbar = nil
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Revert to accessory policy after close without hiding the entire app.
        // Hiding here causes the panel to blink even though only the settings
        // window is being dismissed.
        clearCloseObserver()
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.window = nil
                self?.hostingController = nil
                self?.clearCloseObserver()
                DispatchQueue.main.async {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }

        self.hostingController = hostingController
        self.window = window
    }

    static func bundleAppIcon() -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        image.size = NSSize(width: 256, height: 256)
        return image
    }
}
