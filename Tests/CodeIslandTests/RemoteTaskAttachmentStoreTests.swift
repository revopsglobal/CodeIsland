import Foundation
import XCTest
@testable import CodeIsland

final class RemoteTaskAttachmentStoreTests: XCTestCase {
    func testRejectsFilenameTraversalAbsoluteAndEncodedSeparators() throws {
        let fixture = try AttachmentFixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        let invalidNames = [
            "../secret.txt", "/tmp/secret.txt", "folder/name.txt", "folder\\name.txt",
            "folder%2Fname.txt", "folder%5Cname.txt", "..%2Fsecret.txt",
        ]

        for name in invalidNames {
            XCTAssertThrowsError(
                try store.stage(
                    data: Data("safe".utf8),
                    taskID: UUID(),
                    attachmentID: UUID().uuidString,
                    displayName: name,
                    mediaType: "text/plain"
                ),
                "Expected \(name) to be rejected"
            )
        }
    }

    func testComputesByteCountAndSHA256FromStoredBytes() throws {
        let fixture = try AttachmentFixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        let bytes = Data("hello CodeIsland".utf8)

        let staged = try store.stage(
            data: bytes,
            taskID: UUID(),
            attachmentID: "attachment-1",
            displayName: "context.txt",
            mediaType: "text/plain"
        )

        XCTAssertEqual(staged.descriptor.byteCount, Int64(bytes.count))
        XCTAssertEqual(staged.descriptor.sha256, "f6e69dec9e0e166c012d2064320c96c568fce5ef472cdc063cfb0e52c9fab1c4")
        XCTAssertEqual(try Data(contentsOf: staged.url), bytes)
    }

    func testEnforcesPerFileAndPerTaskByteLimits() throws {
        let fixture = try AttachmentFixture()
        defer { fixture.remove() }
        XCTAssertEqual(RemoteTaskAttachmentStore.defaultPerFileLimit, 25 * 1_024 * 1_024)
        XCTAssertEqual(RemoteTaskAttachmentStore.defaultPerTaskLimit, 50 * 1_024 * 1_024)
        let store = fixture.makeStore(perFileLimit: 4, perTaskLimit: 7)
        let taskID = UUID()

        XCTAssertThrowsError(try store.stage(
            data: Data(repeating: 1, count: 5),
            taskID: taskID,
            attachmentID: "too-large",
            displayName: "large.bin",
            mediaType: "application/octet-stream"
        ))
        _ = try store.stage(
            data: Data(repeating: 1, count: 4),
            taskID: taskID,
            attachmentID: "first",
            displayName: "first.bin",
            mediaType: "application/octet-stream"
        )
        XCTAssertThrowsError(try store.stage(
            data: Data(repeating: 2, count: 4),
            taskID: taskID,
            attachmentID: "second",
            displayName: "second.bin",
            mediaType: "application/octet-stream"
        ))
    }

    func testRecordsTypeMismatchAndNeverMakesAttachmentExecutable() throws {
        let fixture = try AttachmentFixture()
        defer { fixture.remove() }
        let staged = try fixture.makeStore().stage(
            data: Data("#!/bin/sh\necho unsafe".utf8),
            taskID: UUID(),
            attachmentID: "script",
            displayName: "script.sh",
            mediaType: "image/png"
        )

        XCTAssertTrue(staged.hasMediaTypeMismatch)
        XCTAssertFalse(staged.isExecutable)
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: staged.url.path)[.posixPermissions] as? NSNumber
        ).intValue
        XCTAssertEqual(permissions & 0o111, 0)
    }

    func testCleanupRemovesOnlyExactTaskInbox() throws {
        let fixture = try AttachmentFixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        let firstTask = UUID()
        let secondTask = UUID()
        let first = try store.stage(
            data: Data("one".utf8), taskID: firstTask, attachmentID: "one",
            displayName: "one.txt", mediaType: "text/plain"
        )
        let second = try store.stage(
            data: Data("two".utf8), taskID: secondTask, attachmentID: "two",
            displayName: "two.txt", mediaType: "text/plain"
        )

        try store.cleanup(taskID: firstTask)

        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
    }

    func testSymlinkCannotEscapeTaskScopedDirectory() throws {
        let fixture = try AttachmentFixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        let taskID = UUID()
        let outside = try fixture.directory("outside")
        let taskURL = fixture.baseURL.appendingPathComponent(taskID.uuidString.lowercased())
        try FileManager.default.createDirectory(at: fixture.baseURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: taskURL, withDestinationURL: outside)

        XCTAssertThrowsError(try store.stage(
            data: Data("escape".utf8),
            taskID: taskID,
            attachmentID: "payload",
            displayName: "payload.txt",
            mediaType: "text/plain"
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("payload").path))
    }
}

private final class AttachmentFixture {
    let root: URL
    var baseURL: URL { root.appendingPathComponent("Attachments", isDirectory: true) }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandAttachments-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeStore(
        perFileLimit: Int64 = RemoteTaskAttachmentStore.defaultPerFileLimit,
        perTaskLimit: Int64 = RemoteTaskAttachmentStore.defaultPerTaskLimit
    ) -> RemoteTaskAttachmentStore {
        RemoteTaskAttachmentStore(
            baseURL: baseURL,
            perFileLimit: perFileLimit,
            perTaskLimit: perTaskLimit
        )
    }

    func directory(_ path: String) throws -> URL {
        let result = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        return result
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
