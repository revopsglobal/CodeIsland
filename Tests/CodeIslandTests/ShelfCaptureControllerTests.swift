import Foundation
import XCTest
@testable import CodeIsland

@MainActor
final class ShelfCaptureControllerTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var storageDirectory: URL!
    private var screenshotDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandShelfTests-\(UUID().uuidString)", isDirectory: true)
        storageDirectory = temporaryDirectory.appendingPathComponent("Shelf", isDirectory: true)
        screenshotDirectory = temporaryDirectory.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testImportsDroppedFilesIntoPrivateStoreWithCollisionSafeNamesAndMetadata() throws {
        let source = temporaryDirectory.appendingPathComponent("handoff.txt")
        try Data("first".utf8).write(to: source)
        let controller = makeController()

        let first = try controller.importFile(at: source, source: .drop)
        try Data("second".utf8).write(to: source)
        let second = try controller.importFile(at: source, source: .drop)

        XCTAssertEqual(first.url.lastPathComponent, "handoff.txt")
        XCTAssertEqual(second.url.lastPathComponent, "handoff 2.txt")
        XCTAssertEqual(first.source, .drop)
        XCTAssertEqual(first.byteCount, 5)
        XCTAssertEqual(try String(contentsOf: first.url, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second.url, encoding: .utf8), "second")
        XCTAssertTrue(controller.containsStoredFile(first.url))
    }

    func testRejectsDirectoriesSymlinksAndPathsOutsidePrivateStore() throws {
        let controller = makeController()
        let outside = temporaryDirectory.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let symlink = storageDirectory.appendingPathComponent("escape.txt")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)

        XCTAssertNil(controller.validatedStoredFileURL(path: outside.path))
        XCTAssertNil(controller.validatedStoredFileURL(path: symlink.path))
        XCTAssertThrowsError(try controller.importFile(at: temporaryDirectory, source: .filePicker))
    }

    func testAutomaticScreenshotScanImportsOnlyFilesCreatedAfterPriming() throws {
        let oldScreenshot = screenshotDirectory.appendingPathComponent("Screenshot 2026-07-17 at 9.00.00 AM.png")
        try Data("old".utf8).write(to: oldScreenshot)
        let controller = makeController()
        controller.primeScreenshotDirectory()

        let newScreenshot = screenshotDirectory.appendingPathComponent("Screenshot 2026-07-17 at 10.00.00 AM.png")
        let unrelated = screenshotDirectory.appendingPathComponent("photo.png")
        try Data("new".utf8).write(to: newScreenshot)
        try Data("ignore".utf8).write(to: unrelated)

        let captures = controller.scanForNewScreenshots()

        XCTAssertEqual(captures.count, 1)
        XCTAssertEqual(captures.first?.source, .automaticScreenshot)
        XCTAssertEqual(captures.first?.url.lastPathComponent, newScreenshot.lastPathComponent)
        XCTAssertTrue(controller.scanForNewScreenshots().isEmpty)
    }

    func testStartingScreenshotWatcherDoesNotBlockRemoteRequestActorOnDirectoryIO() throws {
        let controller = ShelfCaptureController(
            storageDirectory: storageDirectory,
            screenshotDirectory: screenshotDirectory,
            screenshotCandidateLoader: {
                Thread.sleep(forTimeInterval: 0.25)
                return []
            }
        )

        let startedAt = CFAbsoluteTimeGetCurrent()
        controller.startWatchingScreenshots()
        let elapsed = CFAbsoluteTimeGetCurrent() - startedAt

        XCTAssertLessThan(elapsed, 0.1, "Starting Shelf must not block Buddy's remote request actor")
        controller.stopWatchingScreenshots()
    }

    func testCompletedSelectionAndRecordingCaptureNotifyExactlyOnce() throws {
        let controller = makeController()
        var captures: [ShelfCaptureController.StoredFile] = []
        controller.onStoredFile = { captures.append($0) }
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let selection = storageDirectory.appendingPathComponent("Selection.png")
        let recording = storageDirectory.appendingPathComponent("Recording.mp4")
        try Data("png".utf8).write(to: selection)
        try Data("mp4".utf8).write(to: recording)

        try controller.completeCapture(at: selection, source: .selection)
        try controller.completeCapture(at: recording, source: .recording)

        XCTAssertEqual(captures.map(\.source), [.selection, .recording])
        XCTAssertEqual(captures.map(\.url), [selection, recording])
    }

    func testRemovingStoredFileNeverDeletesAnOutsideFile() throws {
        let controller = makeController()
        let source = temporaryDirectory.appendingPathComponent("keep-source.txt")
        try Data("source".utf8).write(to: source)
        let stored = try controller.importFile(at: source, source: .filePicker)

        XCTAssertThrowsError(try controller.removeStoredFile(path: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        try controller.removeStoredFile(path: stored.url.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    private func makeController() -> ShelfCaptureController {
        ShelfCaptureController(
            storageDirectory: storageDirectory,
            screenshotDirectory: screenshotDirectory
        )
    }
}
