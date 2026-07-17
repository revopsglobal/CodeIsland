import XCTest
@testable import CodeIsland

final class SystemNotificationMirrorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testOrdersDeduplicatesAndGroupsSystemNotifications() {
        let entries = [
            entry(id: "mail-old", source: "Mail", title: "Proposal", age: 90),
            entry(id: "calendar", source: "Calendar", title: "Standup", age: 30),
            entry(id: "mail-new", source: "Mail", title: "Proposal", age: 10),
            entry(id: "mail-other", source: "Mail", title: "Invoice", age: 20),
        ]

        let snapshot = SystemNotificationMirror.makeSnapshot(
            candidates: entries,
            providerState: .ready,
            now: now
        )

        XCTAssertEqual(snapshot.systemGroups.map(\.source), ["Mail", "Calendar"])
        XCTAssertEqual(snapshot.systemGroups[0].entries.map(\.id), ["mail-new", "mail-other"])
        XCTAssertEqual(snapshot.systemGroups[1].entries.map(\.id), ["calendar"])
    }

    func testAppliesAgeAndEntryLimitsWithoutDisplacingCodeIslandAlerts() {
        var entries = (0..<8).map { index in
            entry(id: "system-\(index)", source: "Mail", title: "Message \(index)", age: TimeInterval(index))
        }
        entries.append(entry(
            id: "approval",
            source: "Codex",
            title: "Approval required",
            age: 120,
            origin: .codeIslandAction,
            sessionID: "session-1"
        ))
        entries.append(entry(id: "expired", source: "Calendar", title: "Old", age: 90_000))

        let snapshot = SystemNotificationMirror.makeSnapshot(
            candidates: entries,
            providerState: .ready,
            now: now,
            maximumAge: 86_400,
            maximumEntries: 4
        )

        XCTAssertEqual(snapshot.actionRequired.map(\.id), ["approval"])
        XCTAssertEqual(snapshot.systemGroups.flatMap(\.entries).count, 3)
        XCTAssertFalse(snapshot.systemGroups.flatMap(\.entries).contains { $0.id == "expired" })
    }

    func testRedactsSensitiveNotificationContentAndBoundsText() {
        let longBody = String(repeating: "a", count: 600)
        let snapshot = SystemNotificationMirror.makeSnapshot(
            candidates: [
                entry(id: "otp", source: "Messages", title: "Your verification code is 123456", body: "Use 123456 to sign in", age: 0),
                entry(id: "long", source: "Mail", title: String(repeating: "T", count: 200), body: longBody, age: 1),
            ],
            providerState: .ready,
            now: now
        )
        let mirrored = snapshot.systemGroups.flatMap(\.entries)
        let sensitive = mirrored.first { $0.id == "otp" }
        let bounded = mirrored.first { $0.id == "long" }

        XCTAssertEqual(sensitive?.title, "Sensitive notification")
        XCTAssertEqual(sensitive?.body, "Content hidden for privacy")
        XCTAssertEqual(sensitive?.isRedacted, true)
        XCTAssertEqual(bounded?.title.count, 120)
        XCTAssertEqual(bounded?.body.count, 280)
    }

    func testCodeIslandActionsStaySeparateFromSystemHistoryAndDedupeBySession() {
        let snapshot = SystemNotificationMirror.makeSnapshot(
            candidates: [
                entry(id: "approval-old", source: "Codex", title: "Shell", age: 20, origin: .codeIslandAction, sessionID: "session-1"),
                entry(id: "approval-new", source: "Codex", title: "Git push", age: 5, origin: .codeIslandAction, sessionID: "session-1"),
                entry(id: "mail", source: "Mail", title: "Hello", age: 0),
            ],
            providerState: .ready,
            now: now
        )

        XCTAssertEqual(snapshot.actionRequired.map(\.id), ["approval-new"])
        XCTAssertEqual(snapshot.systemGroups.flatMap(\.entries).map(\.id), ["mail"])
    }

    func testUnsupportedAndPermissionStatesHideSystemCandidatesButKeepLocalAlerts() {
        let candidates = [
            entry(id: "system", source: "Mail", title: "Hello", age: 0),
            entry(id: "approval", source: "Claude Code", title: "Approval", age: 0, origin: .codeIslandAction, sessionID: "session-2"),
        ]

        for state in [
            SystemNotificationMirror.ProviderState.unsupported("No public API"),
            .permissionRequired("Permission required"),
        ] {
            let snapshot = SystemNotificationMirror.makeSnapshot(
                candidates: candidates,
                providerState: state,
                now: now
            )
            XCTAssertEqual(snapshot.actionRequired.map(\.id), ["approval"])
            XCTAssertTrue(snapshot.systemGroups.isEmpty)
            XCTAssertEqual(snapshot.providerState, state)
        }
    }

    private func entry(
        id: String,
        source: String,
        title: String,
        body: String = "Details",
        age: TimeInterval,
        origin: SystemNotificationMirror.Origin = .systemNotification,
        sessionID: String? = nil
    ) -> SystemNotificationMirror.Entry {
        .init(
            id: id,
            source: source,
            title: title,
            body: body,
            createdAt: now.addingTimeInterval(-age),
            origin: origin,
            sessionID: sessionID
        )
    }
}
