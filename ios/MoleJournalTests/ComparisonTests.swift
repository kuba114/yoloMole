import XCTest
@testable import MoleJournal

final class ComparisonTests: XCTestCase {
    func testEachSideExcludesTheOtherCheckIn() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let selection = ComparisonSelection(leftID: a, rightID: b)
        XCTAssertEqual(choices(for: .left, selection: selection, newestFirst: [a, b, c]), [a, c])
        XCTAssertEqual(choices(for: .right, selection: selection, newestFirst: [a, b, c]), [b, c])
    }
}
