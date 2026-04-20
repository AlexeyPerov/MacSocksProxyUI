import XCTest
@testable import MacProxyCore

final class HealthCheckServiceTests: XCTestCase {
    func testValidatedExternalIPURLRejectsInvalidValues() {
        XCTAssertNil(HealthCheckService.validatedExternalIPURL(from: ""))
        XCTAssertNil(HealthCheckService.validatedExternalIPURL(from: "http://example.com"))
        XCTAssertNil(HealthCheckService.validatedExternalIPURL(from: "not-a-url"))
    }

    func testValidatedExternalIPURLAcceptsHTTPS() {
        let url = HealthCheckService.validatedExternalIPURL(from: "https://api.ipify.org?format=text")
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "api.ipify.org")
    }
}
