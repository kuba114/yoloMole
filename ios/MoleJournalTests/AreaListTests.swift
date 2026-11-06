import XCTest
@testable import MoleJournal

final class AreaListTests: XCTestCase {
    func testBlankNameCannotBeSaved() {
        XCTAssertFalse(canSaveAreaName("   "))
        XCTAssertTrue(canSaveAreaName(" left shoulder "))
    }
}
