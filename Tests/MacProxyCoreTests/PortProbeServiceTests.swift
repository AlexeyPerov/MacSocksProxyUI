import XCTest
@testable import MacProxyCore

final class PortProbeServiceTests: XCTestCase {
    func testInvalidPortsReturnFalse() async {
        let service = PortProbeService()
        let negative = await service.isListening(port: -1)
        let tooLarge = await service.isListening(port: 70000)
        XCTAssertFalse(negative)
        XCTAssertFalse(tooLarge)
    }
}
