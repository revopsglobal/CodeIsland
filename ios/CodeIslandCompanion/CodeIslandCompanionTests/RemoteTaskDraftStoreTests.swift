import CryptoKit
import XCTest
@testable import CodeIslandCompanion

@MainActor
final class RemoteTaskDraftStoreTests: XCTestCase {
    func testDraftAndIdempotencyKeyPersistBeforeAnyNetworkSubmission() throws {
        let fixture = try DraftFixture()
        defer { fixture.remove() }
        let clientTaskID = UUID()
        let idempotencyKey = UUID()
        let agentOpsTaskID = UUID()

        let draft = try fixture.store.enqueue(.init(
            clientTaskID: clientTaskID,
            idempotencyKey: idempotencyKey,
            agentOpsTaskID: agentOpsTaskID,
            prompt: "Implement and test the task composer",
            workspaceID: "workspace-a",
            provider: .codex
        ))
        let reloaded = fixture.reload()

        XCTAssertEqual(draft.request.clientTaskID, clientTaskID)
        XCTAssertEqual(reloaded.drafts.first?.request.idempotencyKey, idempotencyKey)
        XCTAssertEqual(reloaded.drafts.first?.request.agentOpsTaskID, agentOpsTaskID)
        XCTAssertEqual(reloaded.drafts.first?.localState, .waitingForMac)
        XCTAssertNil(reloaded.drafts.first?.hostTaskID)
    }

    func testAttachmentIsCopiedPrivatelyAndDescriptorComesFromStoredBytes() throws {
        let fixture = try DraftFixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("context.txt")
        let bytes = Data("private mobile context".utf8)
        try bytes.write(to: source)

        let draft = try fixture.store.enqueue(.init(
            prompt: "Use the attached context",
            workspaceID: "workspace-a",
            provider: .claude,
            attachments: [.init(url: source, displayName: "context.txt", mediaType: "text/plain")]
        ))
        let attachment = try XCTUnwrap(draft.attachments.first)
        let storedURL = try fixture.store.attachmentURL(draftID: draft.id, attachmentID: attachment.descriptor.id)
        let attributes = try FileManager.default.attributesOfItem(atPath: storedURL.path)
        let expectedHash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()

        XCTAssertNotEqual(storedURL.standardizedFileURL, source.standardizedFileURL)
        XCTAssertTrue(storedURL.path.hasPrefix(fixture.attachments.path))
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, 0o600)
        XCTAssertEqual(attachment.descriptor.byteCount, Int64(bytes.count))
        XCTAssertEqual(attachment.descriptor.sha256, expectedHash)
    }

    func testAcceptedDraftKeepsVisibleIdentityUntilAttachmentsFinish() throws {
        let fixture = try DraftFixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("screen.png")
        try Data([1, 2, 3]).write(to: source)
        let draft = try fixture.store.enqueue(.init(
            prompt: "Use this screenshot",
            workspaceID: "workspace-a",
            provider: .codex,
            attachments: [.init(url: source, displayName: "screen.png", mediaType: "image/png")]
        ))
        let hostID = UUID()

        try fixture.store.markAccepted(draftID: draft.id, hostTaskID: hostID)
        XCTAssertEqual(fixture.store.drafts.first?.visibleID, draft.request.clientTaskID)
        XCTAssertEqual(fixture.store.drafts.first?.hostTaskID, hostID)

        try fixture.store.markAttachmentUploaded(
            draftID: draft.id,
            attachmentID: try XCTUnwrap(draft.attachments.first?.descriptor.id)
        )
        try fixture.store.finishIfUploaded(draftID: draft.id)
        XCTAssertTrue(fixture.store.drafts.isEmpty)
    }
}

@MainActor
private final class DraftFixture {
    let root: URL
    let snapshot: URL
    let attachments: URL
    let store: RemoteTaskDraftStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeIslandDraftStore-\(UUID().uuidString)", isDirectory: true)
        snapshot = root.appendingPathComponent("drafts.json")
        attachments = root.appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = RemoteTaskDraftStore(snapshotURL: snapshot, attachmentDirectory: attachments)
    }

    func reload() -> RemoteTaskDraftStore {
        RemoteTaskDraftStore(snapshotURL: snapshot, attachmentDirectory: attachments)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
