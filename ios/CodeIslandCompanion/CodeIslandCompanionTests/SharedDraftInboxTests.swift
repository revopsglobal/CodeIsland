import Foundation
import XCTest
@testable import CodeIslandCompanion

final class SharedDraftInboxTests: XCTestCase {
    func testStoresTextURLImageAndFileUntilMainAppAcknowledges() throws {
        let fixture = try InboxFixture()
        defer { fixture.remove() }
        let manifest = try fixture.inbox.store(
            text: "Review this page\n\nhttps://example.com/spec",
            files: [
                .init(data: Data([0x89, 0x50, 0x4E, 0x47]), displayName: "reference.png", mediaType: "image/png"),
                .init(data: Data("context".utf8), displayName: "context.txt", mediaType: "text/plain"),
            ]
        )

        let claimed = try XCTUnwrap(fixture.inbox.claimNext())
        XCTAssertEqual(claimed.manifest, manifest)
        XCTAssertEqual(claimed.manifest.attachments.map(\.displayName), ["reference.png", "context.txt"])
        XCTAssertEqual(claimed.attachmentURLs.count, 2)
        XCTAssertNotNil(try fixture.inbox.claimNext(), "Claiming must not delete data before private-store import")

        try fixture.inbox.acknowledge(manifest.id)
        XCTAssertNil(try fixture.inbox.claimNext())
    }

    func testDuplicateActivationWithSameIDIsIdempotent() throws {
        let fixture = try InboxFixture()
        defer { fixture.remove() }
        let id = UUID()
        let first = try fixture.inbox.store(id: id, text: "Original", files: [])
        let replay = try fixture.inbox.store(id: id, text: "Replacement", files: [])

        XCTAssertEqual(replay, first)
        XCTAssertEqual(try fixture.inbox.claimNext()?.manifest.text, "Original")
    }

    func testRejectsEmptyUnsupportedOversizedAndTraversalInputs() throws {
        let fixture = try InboxFixture()
        defer { fixture.remove() }

        XCTAssertThrowsError(try fixture.inbox.store(text: "  ", files: [])) {
            XCTAssertEqual($0 as? SharedDraftInbox.InboxError, .emptyDraft)
        }
        XCTAssertThrowsError(try fixture.inbox.store(text: nil, files: [
            .init(data: Data([0x00]), displayName: "file", mediaType: "binary")
        ])) {
            XCTAssertEqual($0 as? SharedDraftInbox.InboxError, .invalidFile)
        }
        XCTAssertThrowsError(try fixture.inbox.store(text: nil, files: [
            .init(data: Data([0x00]), displayName: "../token.txt", mediaType: "text/plain")
        ])) {
            XCTAssertEqual($0 as? SharedDraftInbox.InboxError, .invalidFile)
        }
        XCTAssertThrowsError(try fixture.inbox.store(text: nil, files: [
            .init(data: Data(repeating: 0x00, count: 25 * 1_024 * 1_024 + 1), displayName: "large.bin", mediaType: "application/octet-stream")
        ])) {
            XCTAssertEqual($0 as? SharedDraftInbox.InboxError, .fileTooLarge)
        }
    }

    func testOrdersDraftsDeterministicallyByCreationTime() throws {
        let fixture = try InboxFixture()
        defer { fixture.remove() }
        let firstID = UUID()
        let secondID = UUID()
        _ = try fixture.inbox.store(id: firstID, text: "First", files: [])
        _ = try fixture.inbox.store(id: secondID, text: "Second", files: [])

        XCTAssertEqual(try fixture.inbox.claimNext()?.manifest.id, firstID)
        try fixture.inbox.acknowledge(firstID)
        XCTAssertEqual(try fixture.inbox.claimNext()?.manifest.id, secondID)
    }
}

private final class InboxFixture {
    let root: URL
    let inbox: SharedDraftInbox

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandSharedInbox-\(UUID().uuidString)", isDirectory: true)
        var tick = Date(timeIntervalSince1970: 1_000)
        inbox = try SharedDraftInbox(rootURL: root) {
            defer { tick = tick.addingTimeInterval(1) }
            return tick
        }
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
