import AppKit
import ApplicationServices
import SwiftUI

enum WindowLayout: String, CaseIterable, Identifiable, Equatable {
    case topLeft
    case leftHalf
    case maximize
    case rightHalf
    case topRight
    case bottomLeft
    case leftThird
    case centerThird
    case rightThird
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .leftHalf: "Left half"
        case .maximize: "Maximize"
        case .rightHalf: "Right half"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .leftThird: "Left third"
        case .centerThird: "Center third"
        case .rightThird: "Right third"
        case .bottomRight: "Bottom right"
        }
    }

    var symbol: String {
        switch self {
        case .topLeft: "rectangle.lefthalf.inset.filled.arrow.up"
        case .leftHalf: "rectangle.lefthalf.inset.filled"
        case .maximize: "rectangle.inset.filled"
        case .rightHalf: "rectangle.righthalf.inset.filled"
        case .topRight: "rectangle.righthalf.inset.filled.arrow.up"
        case .bottomLeft: "rectangle.lefthalf.inset.filled.arrow.down"
        case .leftThird: "rectangle.split.3x1.fill"
        case .centerThird: "rectangle.split.3x1"
        case .rightThird: "rectangle.split.3x1.fill"
        case .bottomRight: "rectangle.righthalf.inset.filled.arrow.down"
        }
    }

    var placement: WindowManagerController.Placement {
        switch self {
        case .topLeft: .topLeft
        case .leftHalf: .left
        case .maximize: .maximize
        case .rightHalf: .right
        case .topRight: .topRight
        case .bottomLeft: .bottomLeft
        case .leftThird: .leftThird
        case .centerThird: .centerThird
        case .rightThird: .rightThird
        case .bottomRight: .bottomRight
        }
    }
}

enum WindowLayoutGeometry {
    static let chooserSize = CGSize(width: 540, height: 176)
    static let activationWidth: CGFloat = 220
    static let hoverDelay: TimeInterval = 0.16
    static let hysteresis: CGFloat = 34

    static func frame(
        for placement: WindowManagerController.Placement,
        in visible: CGRect
    ) -> CGRect {
        switch placement {
        case .left:
            CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .right:
            CGRect(x: visible.midX, y: visible.minY, width: visible.width / 2, height: visible.height)
        case .maximize:
            visible
        case .leftThird:
            CGRect(x: visible.minX, y: visible.minY, width: visible.width / 3, height: visible.height)
        case .centerThird:
            CGRect(x: visible.minX + visible.width / 3, y: visible.minY, width: visible.width / 3, height: visible.height)
        case .rightThird:
            CGRect(x: visible.maxX - visible.width / 3, y: visible.minY, width: visible.width / 3, height: visible.height)
        case .topLeft:
            CGRect(x: visible.minX, y: visible.midY, width: visible.width / 2, height: visible.height / 2)
        case .topRight:
            CGRect(x: visible.midX, y: visible.midY, width: visible.width / 2, height: visible.height / 2)
        case .bottomLeft:
            CGRect(x: visible.minX, y: visible.minY, width: visible.width / 2, height: visible.height / 2)
        case .bottomRight:
            CGRect(x: visible.midX, y: visible.minY, width: visible.width / 2, height: visible.height / 2)
        }
    }

    static func activationFrame(for screen: WindowLayoutScreen) -> CGRect {
        let height = max(screen.topBarHeight + 28, 64)
        return CGRect(
            x: screen.frame.midX - activationWidth / 2,
            y: screen.frame.maxY - height,
            width: activationWidth,
            height: height
        )
    }

    static func chooserFrame(for screen: WindowLayoutScreen) -> CGRect {
        let width = min(chooserSize.width, screen.frame.width - 40)
        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - screen.topBarHeight - chooserSize.height - 8,
            width: width,
            height: chooserSize.height
        )
    }

    static func retentionFrame(for screen: WindowLayoutScreen) -> CGRect {
        activationFrame(for: screen)
            .union(chooserFrame(for: screen))
            .insetBy(dx: -hysteresis, dy: -hysteresis)
    }

    static func layout(at point: CGPoint, in chooserFrame: CGRect) -> WindowLayout? {
        guard chooserFrame.contains(point) else { return nil }
        let columnWidth = chooserFrame.width / 5
        let rowHeight = chooserFrame.height / 2
        let column = min(max(Int((point.x - chooserFrame.minX) / columnWidth), 0), 4)
        let rowFromTop = min(max(Int((chooserFrame.maxY - point.y) / rowHeight), 0), 1)
        return WindowLayout.allCases[rowFromTop * 5 + column]
    }
}

struct WindowLayoutScreen: Equatable {
    let id: String
    let frame: CGRect
    let visibleFrame: CGRect
    let topBarHeight: CGFloat
}

enum WindowLayoutDropPhase: Equatable {
    case idle
    case hovering
    case choosing
}

enum WindowLayoutDropCancellation: Equatable {
    case accessibilityDenied
    case ineligibleWindow
    case leftTarget
    case releasedBeforeChoice
}

struct WindowLayoutDropInteraction: Equatable {
    private(set) var phase: WindowLayoutDropPhase = .idle
    private(set) var screen: WindowLayoutScreen?
    private(set) var highlightedLayout: WindowLayout?
    private(set) var enteredAt: Date?
    private(set) var cancellation: WindowLayoutDropCancellation?

    var isChooserVisible: Bool { phase == .choosing }

    mutating func updateDrag(
        point: CGPoint,
        screens: [WindowLayoutScreen],
        at date: Date,
        accessibilityAuthorized: Bool,
        targetEligible: Bool
    ) {
        guard accessibilityAuthorized else {
            reset(cancellation: .accessibilityDenied)
            return
        }
        guard targetEligible else {
            reset(cancellation: .ineligibleWindow)
            return
        }

        switch phase {
        case .idle:
            guard let target = screens.first(where: {
                WindowLayoutGeometry.activationFrame(for: $0).contains(point)
            }) else { return }
            phase = .hovering
            screen = target
            enteredAt = date
            cancellation = nil

        case .hovering:
            guard let screen else {
                reset(cancellation: .leftTarget)
                return
            }
            let activation = WindowLayoutGeometry.activationFrame(for: screen)
                .insetBy(dx: -12, dy: -12)
            guard activation.contains(point) else {
                reset(cancellation: .leftTarget)
                return
            }
            if let enteredAt, date.timeIntervalSince(enteredAt) >= WindowLayoutGeometry.hoverDelay {
                phase = .choosing
                highlightedLayout = .maximize
            }

        case .choosing:
            guard let screen,
                  WindowLayoutGeometry.retentionFrame(for: screen).contains(point)
            else {
                reset(cancellation: .leftTarget)
                return
            }
            if let layout = WindowLayoutGeometry.layout(
                at: point,
                in: WindowLayoutGeometry.chooserFrame(for: screen)
            ) {
                highlightedLayout = layout
            }
        }
    }

    mutating func release() -> (WindowLayout, WindowLayoutScreen)? {
        guard phase == .choosing, let highlightedLayout, let screen else {
            reset(cancellation: .releasedBeforeChoice)
            return nil
        }
        let result = (highlightedLayout, screen)
        reset(cancellation: nil)
        return result
    }

    mutating func cancel() {
        reset(cancellation: .leftTarget)
    }

    private mutating func reset(cancellation: WindowLayoutDropCancellation?) {
        phase = .idle
        screen = nil
        highlightedLayout = nil
        enteredAt = nil
        self.cancellation = cancellation
    }
}

@MainActor
final class WindowLayoutDropController {
    static let shared = WindowLayoutDropController()

    private(set) var interaction = WindowLayoutDropInteraction()
    private var globalMonitor: Any?
    private var hoverTask: Task<Void, Never>?
    private var chooserWindow: NSPanel?

    func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                switch event.type {
                case .leftMouseDragged:
                    self.handleDrag(at: NSEvent.mouseLocation)
                case .leftMouseUp:
                    self.handleRelease()
                default:
                    break
                }
            }
        }
    }

    func stop() {
        hoverTask?.cancel()
        hoverTask = nil
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        interaction.cancel()
        hideChooser()
    }

    private func handleDrag(at point: CGPoint) {
        let previousPhase = interaction.phase
        interaction.updateDrag(
            point: point,
            screens: Self.currentScreens(),
            at: Date(),
            accessibilityAuthorized: WindowManagerController.isAuthorized,
            targetEligible: WindowManagerController.frontWindowIsEligibleForLayout
        )

        if interaction.phase == .hovering, previousPhase != .hovering {
            hoverTask?.cancel()
            hoverTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled,
                      CGEventSource.buttonState(.combinedSessionState, button: .left)
                else { return }
                self?.handleDrag(at: NSEvent.mouseLocation)
            }
        }

        if interaction.isChooserVisible, let screen = interaction.screen {
            showChooser(on: screen)
        } else if interaction.phase == .idle {
            hideChooser()
        }
    }

    private func handleRelease() {
        hoverTask?.cancel()
        hoverTask = nil
        let selection = interaction.release()
        hideChooser()
        guard let (layout, descriptor) = selection,
              let screen = NSScreen.screens.first(where: {
                  Self.screenID($0) == descriptor.id
              })
        else { return }
        if WindowManagerController.placeFrontWindow(layout.placement, on: screen) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func showChooser(on screen: WindowLayoutScreen) {
        let frame = WindowLayoutGeometry.chooserFrame(for: screen)
        let rootView = WindowLayoutDropChooser(highlighted: interaction.highlightedLayout)
        if let chooserWindow {
            chooserWindow.setFrame(frame, display: true)
            chooserWindow.contentView = NSHostingView(rootView: rootView)
            chooserWindow.orderFrontRegardless()
            return
        }

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none
        panel.contentView = NSHostingView(rootView: rootView)
        panel.orderFrontRegardless()
        chooserWindow = panel
    }

    private func hideChooser() {
        chooserWindow?.orderOut(nil)
        chooserWindow = nil
    }

    private static func currentScreens() -> [WindowLayoutScreen] {
        NSScreen.screens.map {
            WindowLayoutScreen(
                id: screenID($0),
                frame: $0.frame,
                visibleFrame: $0.visibleFrame,
                topBarHeight: ScreenDetector.topBarHeight(for: $0)
            )
        }
    }

    private static func screenID(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return ScreenDetector.signature(for: screen)
    }
}

private struct WindowLayoutDropChooser: View {
    let highlighted: WindowLayout?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("DROP TO ARRANGE", systemImage: "rectangle.3.group.fill")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(1.1)
                Spacer()
                Text("Release to place")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .foregroundStyle(.orange)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(WindowLayout.allCases) { layout in
                    VStack(spacing: 5) {
                        Image(systemName: layout.symbol)
                            .font(.system(size: 16, weight: .bold))
                        Text(layout.title)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundStyle(highlighted == layout ? .black : .white.opacity(0.72))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(highlighted == layout ? Color.orange : Color.white.opacity(0.08))
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(3)
    }
}
