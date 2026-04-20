import XCTest
@testable import MacProxyCore

final class SshProcessServiceTests: XCTestCase {
    func testParseFailureMatchesAuthentication() {
        let parsed = SshProcessService.parseFailure(
            from: [
                "debug line",
                "Authentication failed."
            ]
        )
        XCTAssertEqual(parsed, .authenticationFailed)
    }

    func testParseFailureUsesLastActionableLine() {
        let parsed = SshProcessService.parseFailure(
            from: [
                "Connection refused",
                "Permission denied (publickey,password)."
            ]
        )
        XCTAssertEqual(parsed, .permissionDenied)
    }

    func testParseFailureReturnsNilForUnrecognizedStderr() {
        XCTAssertNil(SshProcessService.parseFailure(from: ["no issue found"]))
    }
}
