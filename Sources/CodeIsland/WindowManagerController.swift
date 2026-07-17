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
    }

    static var isAuthorized: Bool { AXIsProcessTrusted() }

    static func placeFrontWindow(_ placement: Placement) -> Bool {
        guard isAuthorized,
              let app = NSWorkspace.shared.frontmostApplication,
              let screen = NSScreen.main
        else { return false }

        let application = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success,
        let windowValue,
        CFGetTypeID(windowValue) == AXUIElementGetTypeID()
        else { return false }

        let window = unsafeBitCast(windowValue, to: AXUIElement.self)
        let visible = screen.visibleFrame
        let frame: CGRect
        switch placement {
        case .left:
            frame = CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .right:
            frame = CGRect(x: visible.midX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .maximize:
            frame = visible
        }

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
}
