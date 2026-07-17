import AppKit
import SwiftUI

@MainActor
final class TeleprompterWindowController {
    static let shared = TeleprompterWindowController()
    private var window: NSWindow?

    func show(text: String) {
        let view = MacTeleprompterView(text: text) { [weak self] in
            self?.window?.close()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "CodeIsland Teleprompter"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct MacTeleprompterView: View {
    let text: String
    let close: () -> Void
    @State private var fontSize: Double = 42

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TELEPROMPTER")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.orange)
                Spacer()
                Button { fontSize = max(24, fontSize - 2) } label: { Image(systemName: "textformat.size.smaller") }
                Button { fontSize = min(72, fontSize + 2) } label: { Image(systemName: "textformat.size.larger") }
                Button("Done", action: close)
            }
            .buttonStyle(.borderless)
            .padding(16)

            ScrollView {
                Text(text)
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(13)
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding(.vertical, 80)
            }
        }
        .background(Color.black)
    }
}
