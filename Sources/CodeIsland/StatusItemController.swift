import AppKit

extension UserDefaults {
    @objc dynamic var hideWhenNoSession: Bool {
        bool(forKey: SettingsKey.hideWhenNoSession)
    }
}

@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var observation: NSKeyValueObservation?
    private lazy var menu: NSMenu = makeMenu()
    /// True while an approval/question is waiting — forces the item visible and amber.
    private var pending = false

    func startObserving() {
        syncVisibility()
        observation = UserDefaults.standard.observe(
            \.hideWhenNoSession, options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor in self?.syncVisibility() }
        }
    }

    /// Crest-parity amber menu-bar indicator. While an approval is pending the
    /// status item is force-shown with an amber alert glyph, even if the user
    /// otherwise hides it when idle; it reverts on resolve.
    func setPending(_ isPending: Bool) {
        guard isPending != pending else { return }
        pending = isPending
        if isPending {
            showStatusItem()
        } else {
            syncVisibility()
        }
        refreshButtonAppearance()
    }

    private func syncVisibility() {
        if pending || SettingsManager.shared.hideWhenNoSession {
            showStatusItem()
        } else {
            hideStatusItem()
        }
        refreshButtonAppearance()
    }

    private func showStatusItem() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.menu = menu
            statusItem = item
        }
        refreshButtonAppearance()
    }

    /// Amber alert glyph while pending, otherwise the normal app icon.
    private func refreshButtonAppearance() {
        guard let button = statusItem?.button else { return }
        if pending {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
                .applying(.init(paletteColors: [NSColor.systemOrange]))
            let symbol = NSImage(
                systemSymbolName: "bell.badge.fill",
                accessibilityDescription: "Approval waiting"
            )?.withSymbolConfiguration(config)
            symbol?.isTemplate = false
            button.image = symbol
            button.toolTip = "CodeIsland — approval waiting"
        } else {
            let icon = SettingsWindowController.bundleAppIcon()
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = false
            button.image = icon
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "CodeIsland"
        }
    }

    private func hideStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: L10n.shared["settings_ellipsis"],
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.shared["quit"],
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openSettings() {
        Task { @MainActor in
            SettingsWindowController.shared.show()
        }
    }

    @objc private func quitApp() {
        ApplicationQuitController.shared.requestQuit()
    }
}
