import AppKit
import ApplicationServices

/// Allow-listed window placement for the current foreground app. Accessibility
/// must already be granted locally; a remote request never triggers the trust
/// prompt or gains broader arbitrary AX access.
enum WindowManagerController {
    enum Placement {
        case left
        case right
        case maximize
        case leftThird
        case centerThird
        case rightThird
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    static var isAuthorized: Bool { AXIsProcessTrusted() }

    static func placeFrontWindow(_ placement: Placement) -> Bool {
        guard isAuthorized,
              let app = NSWorkspace.shared.frontmostApplication,
              isEligibleTarget(
                  processIdentifier: app.processIdentifier,
                  currentProcessIdentifier: ProcessInfo.processInfo.processIdentifier
              ),
              let screen = NSScreen.main
        else { return false }

        return placeFrontWindow(placement, for: app, on: screen)
    }

    static func placeFrontWindow(_ placement: Placement, on screen: NSScreen) -> Bool {
        guard isAuthorized,
              let app = NSWorkspace.shared.frontmostApplication,
              isEligibleTarget(
                  processIdentifier: app.processIdentifier,
                  currentProcessIdentifier: ProcessInfo.processInfo.processIdentifier
              )
        else { return false }

        return placeFrontWindow(placement, for: app, on: screen)
    }

    static var frontWindowIsEligibleForLayout: Bool {
        guard isAuthorized,
              let app = NSWorkspace.shared.frontmostApplication,
              isEligibleTarget(
                  processIdentifier: app.processIdentifier,
                  currentProcessIdentifier: ProcessInfo.processInfo.processIdentifier
              ),
              focusedWindow(for: app) != nil
        else { return false }
        return true
    }

    nonisolated static func isEligibleTarget(
        processIdentifier: pid_t,
        currentProcessIdentifier: pid_t
    ) -> Bool {
        processIdentifier > 0 && processIdentifier != currentProcessIdentifier
    }

    private static func placeFrontWindow(
        _ placement: Placement,
        for app: NSRunningApplication,
        on screen: NSScreen
    ) -> Bool {
        guard let window = focusedWindow(for: app) else { return false }

        let frame = WindowLayoutGeometry.frame(for: placement, in: screen.visibleFrame)
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else { return false }
        let positionResult = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            positionValue
        )
        let sizeResult = AXUIElementSetAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            sizeValue
        )
        return positionResult == .success && sizeResult == .success
    }

    private static func focusedWindow(for app: NSRunningApplication) -> AXUIElement? {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success,
        let windowValue,
        CFGetTypeID(windowValue) == AXUIElementGetTypeID()
        else { return nil }

        let window = unsafeBitCast(windowValue, to: AXUIElement.self)
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            window,
            kAXPositionAttribute as CFString,
            &settable
        ) == .success,
        settable.boolValue
        else { return nil }
        settable = false
        guard AXUIElementIsAttributeSettable(
            window,
            kAXSizeAttribute as CFString,
            &settable
        ) == .success,
        settable.boolValue
        else { return nil }
        return window
    }
}
