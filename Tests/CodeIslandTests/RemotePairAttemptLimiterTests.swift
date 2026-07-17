import XCTest
@testable import CodeIsland

final class RemotePairAttemptLimiterTests: XCTestCase {
    func testBlocksAfterFailureBudgetAndResets() {
        let now = Date(timeIntervalSince1970: 10_000)
        var limiter = RemotePairAttemptLimiter(maximumFailures: 3, window: 60)

        XCTAssertTrue(limiter.canAttempt(at: now))
        limiter.recordFailure(at: now)
        limiter.recordFailure(at: now)
        limiter.recordFailure(at: now)
        XCTAssertFalse(limiter.canAttempt(at: now))

        limiter.reset()
        XCTAssertTrue(limiter.canAttempt(at: now))
    }

    func testFailureBudgetExpiresWithWindow() {
        let now = Date(timeIntervalSince1970: 20_000)
        var limiter = RemotePairAttemptLimiter(maximumFailures: 1, window: 60)

        limiter.recordFailure(at: now)
        XCTAssertFalse(limiter.canAttempt(at: now.addingTimeInterval(59)))
        XCTAssertTrue(limiter.canAttempt(at: now.addingTimeInterval(60)))
    }
}
