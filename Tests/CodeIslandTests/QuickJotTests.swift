import XCTest
@testable import CodeIsland

@MainActor
final class QuickJotTests: XCTestCase {
    func testSubmitUsesTheExplicitTaskDestinationAndTrimsText() {
        var tasks: [String] = []
        var notes: [String] = []
        let session = QuickJotSession(
            saveTask: { tasks.append($0); return true },
            saveNote: { notes.append($0); return true }
        )

        session.begin(destination: .task)
        session.replaceText("  Call the bank  ")

        XCTAssertTrue(session.submit())
        XCTAssertEqual(tasks, ["Call the bank"])
        XCTAssertTrue(notes.isEmpty)
        XCTAssertFalse(session.isPresented)
    }

    func testReturnSavesNoteAndEscapeCancelsWithoutWriting() {
        var notes: [String] = []
        let session = QuickJotSession(
            saveTask: { _ in XCTFail("Wrong destination"); return false },
            saveNote: { notes.append($0); return true }
        )

        session.begin(destination: .note)
        session.replaceText("Capture the customer quote")
        XCTAssertEqual(session.handle(.return), .saved)
        XCTAssertEqual(notes, ["Capture the customer quote"])

        session.begin(destination: .note)
        session.replaceText("Do not save")
        XCTAssertEqual(session.handle(.escape), .cancelled)
        XCTAssertEqual(notes, ["Capture the customer quote"])
        XCTAssertEqual(session.text, "")
    }

    func testUndoRestoresPreviousDraftText() {
        let session = QuickJotSession(saveTask: { _ in true }, saveNote: { _ in true })
        session.begin(destination: .note)
        session.replaceText("First draft")
        session.replaceText("Second draft")

        XCTAssertEqual(session.handle(.undo), .editing)
        XCTAssertEqual(session.text, "First draft")
    }

    func testFailedWriteKeepsPanelOpenAndShowsDestinationSpecificError() {
        let session = QuickJotSession(saveTask: { _ in false }, saveNote: { _ in true })
        session.begin(destination: .task)
        session.replaceText("Task without Reminders permission")

        XCTAssertFalse(session.submit())
        XCTAssertTrue(session.isPresented)
        XCTAssertEqual(session.errorMessage, "Could not save the task")
    }

    func testSavedNoteIsVisibleInRemoteWorkSnapshot() throws {
        let suiteName = "QuickJotTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let data = PersonalHubDataModel(defaults: defaults)
        let session = QuickJotSession(
            saveTask: { _ in false },
            saveNote: data.addNote
        )
        session.begin(destination: .note)
        session.replaceText("Visible from Buddy")
        XCTAssertTrue(session.submit())

        let snapshot = PersonalHubService(data: data).snapshot(
            appState: AppState(),
            requestedMode: .work,
            serverName: "Quick Jot Test Mac"
        )
        let notes = try XCTUnwrap(snapshot.modules.first(where: { $0.id == .notes }))
        XCTAssertTrue(notes.items.contains(where: { $0.title == "Visible from Buddy" }))
    }
}
