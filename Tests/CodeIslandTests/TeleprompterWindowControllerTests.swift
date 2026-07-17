import AppKit
import XCTest
@testable import CodeIsland

final class TeleprompterWindowControllerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testPlaybackAdvancesByElapsedTimeAndWordsPerMinute() {
        var state = TeleprompterPlaybackState(
            text: (1...20).map(String.init).joined(separator: " "),
            wordsPerMinute: 120
        )

        state.play(at: start)
        state.advance(to: start.addingTimeInterval(2))

        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.wordOffset, 4, accuracy: 0.001)
        XCTAssertEqual(state.currentWordIndex, 4)
    }

    func testPauseAndResumeDoNotCountPausedTime() {
        var state = TeleprompterPlaybackState(
            text: (1...40).map(String.init).joined(separator: " "),
            wordsPerMinute: 60
        )

        state.play(at: start)
        state.pause(at: start.addingTimeInterval(3))
        state.play(at: start.addingTimeInterval(30))
        state.advance(to: start.addingTimeInterval(32))

        XCTAssertEqual(state.wordOffset, 5, accuracy: 0.001)
        XCTAssertTrue(state.isPlaying)
    }

    func testWordsPerMinuteAndFontSizeAreClamped() {
        var state = TeleprompterPlaybackState(text: "one two three", wordsPerMinute: 10, fontSize: 4)
        XCTAssertEqual(state.wordsPerMinute, 60)
        XCTAssertEqual(state.fontSize, 24)

        state.setWordsPerMinute(400, at: start)
        state.setFontSize(200)

        XCTAssertEqual(state.wordsPerMinute, 240)
        XCTAssertEqual(state.fontSize, 72)
    }

    func testManualScrollPausesAtExactOffset() {
        var state = TeleprompterPlaybackState(
            text: (1...40).map(String.init).joined(separator: " "),
            wordsPerMinute: 120
        )

        state.play(at: start)
        state.pause(at: start.addingTimeInterval(1.5), reason: .manualScroll)

        XCTAssertFalse(state.isPlaying)
        XCTAssertEqual(state.wordOffset, 3, accuracy: 0.001)
        XCTAssertEqual(state.stopReason, .manualScroll)
    }

    func testEndOfScriptStopsAndPlayRestarts() {
        var state = TeleprompterPlaybackState(text: "one two three", wordsPerMinute: 240)

        state.play(at: start)
        state.advance(to: start.addingTimeInterval(10))

        XCTAssertFalse(state.isPlaying)
        XCTAssertTrue(state.hasReachedEnd)
        XCTAssertEqual(state.stopReason, .reachedEnd)
        XCTAssertEqual(state.progress, 1)

        state.play(at: start.addingTimeInterval(11))
        XCTAssertTrue(state.isPlaying)
        XCTAssertEqual(state.wordOffset, 0)
    }

    func testCloseStopsPlaybackAndClearsTimingAnchor() {
        var state = TeleprompterPlaybackState(text: "one two three four five", wordsPerMinute: 60)
        state.play(at: start)
        state.close(at: start.addingTimeInterval(1))

        XCTAssertFalse(state.isPlaying)
        XCTAssertNil(state.lastTick)
        XCTAssertEqual(state.stopReason, .closed)
        XCTAssertEqual(state.wordOffset, 1, accuracy: 0.001)
    }

    func testSharingExclusionIsBestEffortAndDisclosedHonestly() {
        XCTAssertEqual(TeleprompterSharingPrivacy.requestedSharingType, .none)
        XCTAssertTrue(TeleprompterSharingPrivacy.disclosure.contains("requested"))
        XCTAssertTrue(TeleprompterSharingPrivacy.disclosure.contains("may still"))
    }

    @MainActor
    func testPreferencesPersistWithinPrivateDefaultsSuite() throws {
        let suite = "TeleprompterWindowControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = TeleprompterPlaybackModel(text: "one two three", defaults: defaults)
        first.setWordsPerMinute(210, at: start)
        first.setFontSize(56)

        let second = TeleprompterPlaybackModel(text: "another script", defaults: defaults)
        XCTAssertEqual(second.wordsPerMinute, 210)
        XCTAssertEqual(second.fontSize, 56)
    }
}
