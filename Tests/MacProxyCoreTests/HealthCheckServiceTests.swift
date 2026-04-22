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

    func testValidatedExternalIPURLsFiltersInvalidEntries() {
        let urls = HealthCheckService.validatedExternalIPURLs(from: [
            "https://api.ipify.org?format=text",
            "not-a-url",
            "http://example.com",
            "https://ifconfig.me/ip"
        ])
        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls.map(\.host), ["api.ipify.org", "ifconfig.me"])
    }
}
