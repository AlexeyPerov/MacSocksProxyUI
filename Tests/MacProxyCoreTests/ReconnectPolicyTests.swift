import XCTest
@testable import MacProxyCore

final class ReconnectPolicyTests: XCTestCase {
    func testNonTransientFailuresDoNotRetry() {
        let policy = ReconnectPolicy(jitterRange: 0...0)
        XCTAssertFalse(policy.shouldRetry(parsedFailure: .permissionDenied))
        XCTAssertFalse(policy.shouldRetry(parsedFailure: .authenticationFailed))
        XCTAssertFalse(policy.shouldRetry(parsedFailure: .hostKeyVerificationFailed))
    }

    func testTransientFailuresRetry() {
        let policy = ReconnectPolicy(jitterRange: 0...0)
        XCTAssertTrue(policy.shouldRetry(parsedFailure: .networkUnreachable))
        XCTAssertTrue(policy.shouldRetry(parsedFailure: .connectionRefused))
        XCTAssertTrue(policy.shouldRetry(parsedFailure: nil))
    }

    func testDelayBackoffIsCapped() {
        let policy = ReconnectPolicy(baseDelaySeconds: 2, maxDelaySeconds: 10, jitterRange: 0...0)
        XCTAssertEqual(policy.delaySeconds(forAttempt: 1), 2)
        XCTAssertEqual(policy.delaySeconds(forAttempt: 2), 4)
        XCTAssertEqual(policy.delaySeconds(forAttempt: 3), 8)
        XCTAssertEqual(policy.delaySeconds(forAttempt: 4), 10)
        XCTAssertEqual(policy.delaySeconds(forAttempt: 8), 10)
    }
}
