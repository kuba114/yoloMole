import XCTest
@testable import MoleJournal

final class SessionTests: XCTestCase {
    func testCancelStaysSignedOut() {
        XCTAssertEqual(sessionAfterAppleResult(.cancel, current: .signedOut), .signedOut)
    }

    func testMatchingIDSignsIn() {
        XCTAssertEqual(sessionAfterAppleResult(.matched, current: .signedOut), .signedIn)
    }

    func testDifferentIDLocks() {
        XCTAssertEqual(sessionAfterAppleResult(.differentID, current: .signedOut), .locked)
    }
}
