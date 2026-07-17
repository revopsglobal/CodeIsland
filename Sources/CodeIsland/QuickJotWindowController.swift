import AppKit
import Combine
import SwiftUI

enum QuickJotDestination: String, CaseIterable, Identifiable {
    case task
    case note

    var id: String { rawValue }
    var title: String { self == .task ? "Task" : "Note" }
    var symbol: String { self == .task ? "checklist" : "note.text" }
}

enum QuickJotCommand {
    case escape
    case `return`
    case undo
}

enum QuickJotCommandResult: Equatable {
    case editing
    case saved
    case cancelled
}

@MainActor
final class QuickJotSession: ObservableObject {
    @Published private(set) var destination: QuickJotDestination = .task
    @Published private(set) var text = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPresented = false

    private let saveTask: (String) -> Bool
    private let saveNote: (String) -> Bool
    private var undoHistory: [String] = []

    init(
        saveTask: @escaping (String) -> Bool,
        saveNote: @escaping (String) -> Bool
    ) {
        self.saveTask = saveTask
        self.saveNote = saveNote
    }

    func begin(destination: QuickJotDestination) {
        self.destination = destination
        text = ""
        errorMessage = nil
        undoHistory = []
        isPresented = true
    }

    func setDestination(_ destination: QuickJotDestination) {
        self.destination = destination
        errorMessage = nil
    }

    func replaceText(_ value: String) {
        guard value != text else { return }
        undoHistory.append(text)
        undoHistory = Array(undoHistory.suffix(100))
        text = value
        errorMessage = nil
    }

    @discardableResult
    func submit() -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            errorMessage = destination == .task ? "Enter a task" : "Enter a note"
            return false
        }
        let saved = destination == .task ? saveTask(value) : saveNote(value)
        guard saved else {
            errorMessage = destination == .task
                ? "Could not save the task"
                : "Could not save the note"
            return false
        }
        text = ""
        undoHistory = []
        errorMessage = nil
        isPresented = false
        return true
    }

    func cancel() {
        text = ""
        undoHistory = []
        errorMessage = nil
        isPresented = false
    }

    @discardableResult
    func handle(_ command: QuickJotCommand) -> QuickJotCommandResult {
        switch command {
        case .escape:
            cancel()
            return .cancelled
        case .return:
            return submit() ? .saved : .editing
        case .undo:
            guard let previous = undoHistory.popLast() else { return .editing }
            text = previous
            errorMessage = nil
            return .editing
        }
    }
}

@MainActor
final class QuickJotWindowController: NSObject, NSWindowDelegate {
    static let shared = QuickJotWindowController()

    private let session: QuickJotSession
    private var panel: NSPanel?

    override init() {
        session = QuickJotSession(
            saveTask: { GlancesModel.shared.addReminder(title: $0) },
            saveNote: { PersonalHubDataModel.shared.addNote($0) }
        )
        super.init()
    }

    func show(destination: QuickJotDestination) {
        session.begin(destination: destination)
        let panel = panel ?? makePanel()
        self.panel = panel

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main {
            let frame = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - frame.width / 2,
                y: screen.visibleFrame.maxY - frame.height - 56
            ))
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if session.isPresented { session.cancel() }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 190),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Quick Jot"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: QuickJotPanelView(
            session: session,
            close: { [weak panel] in panel?.close() }
        ))
        return panel
    }
}

private struct QuickJotPanelView: View {
    @ObservedObject var session: QuickJotSession
    let close: () -> Void

    @FocusState private var focused: Bool
    private let accent = Color(red: 1.0, green: 0.69, blue: 0.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Quick Jot", systemImage: session.destination.symbol)
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("⌃⌥\(session.destination == .task ? "T" : "N")")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Picker("Destination", selection: Binding(
                get: { session.destination },
                set: session.setDestination
            )) {
                ForEach(QuickJotDestination.allCases) { destination in
                    Label(destination.title, systemImage: destination.symbol).tag(destination)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField(
                session.destination == .task ? "What needs doing?" : "What do you want to remember?",
                text: Binding(get: { session.text }, set: session.replaceText)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 9))
            .focused($focused)
            .onSubmit {
                if session.handle(.return) == .saved { close() }
            }

            HStack {
                if let error = session.errorMessage {
                    Text(error)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                } else {
                    Text("Return saves · Escape cancels · Command-Z undoes")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save \(session.destination.title)") {
                    if session.submit() { close() }
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.72))
        .onAppear { focused = true }
        .onExitCommand {
            _ = session.handle(.escape)
            close()
        }
    }
}
