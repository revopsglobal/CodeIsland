import XCTest
@testable import CodeIslandCompanion

final class CompanionCommandCenterModelTests: XCTestCase {
    func testAttentionSelectionKeepsTheVisibleItemAcrossReorderedPolls() {
        XCTAssertEqual(
            CompanionAttentionSelection.resolve(
                previousID: "approval-a",
                currentIDs: ["question-b", "approval-a"]
            ),
            "approval-a"
        )
    }

    func testAttentionSelectionFallsBackOnlyWhenTheVisibleItemIsGone() {
        XCTAssertEqual(
            CompanionAttentionSelection.resolve(
                previousID: "approval-a",
                currentIDs: ["question-b", "approval-c"]
            ),
            "question-b"
        )
        XCTAssertNil(
            CompanionAttentionSelection.resolve(
                previousID: "approval-a",
                currentIDs: []
            )
        )
    }

    func testMotionPolicyKeepsRoutinePollsVisuallyInert() {
        XCTAssertFalse(CompanionMotionPolicy.animatesRoutinePoll)
        XCTAssertTrue(
            CompanionMotionPolicy.shouldAnimateNewAttention(
                previousIDs: ["approval-a"],
                currentIDs: ["approval-a", "question-b"],
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            CompanionMotionPolicy.shouldAnimateNewAttention(
                previousIDs: ["approval-a", "question-b"],
                currentIDs: ["question-b", "approval-a"],
                reduceMotion: false
            ),
            "Reordering the same requests during a poll must not animate or rotate the stage"
        )
        XCTAssertFalse(
            CompanionMotionPolicy.shouldAnimateNewAttention(
                previousIDs: ["approval-a"],
                currentIDs: ["approval-a", "question-b"],
                reduceMotion: true
            )
        )
    }
}
