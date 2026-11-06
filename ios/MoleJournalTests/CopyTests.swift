import XCTest
@testable import MoleJournal

final class CopyTests: XCTestCase {
    func testSignInDisclaimer() {
        XCTAssertEqual(
            Copy.signInDisclaimer,
            "A personal photo log of skin areas. It does not diagnose."
        )
    }

    func testPoseAndFailureCopy() {
        XCTAssertEqual(Copy.matchPose, "Match this pose.")
        XCTAssertEqual(
            Copy.framingNote,
            "Fill the frame with the area, hold a steady distance, and use the same lighting next time."
        )
        XCTAssertEqual(
            Copy.cameraRequired,
            "The camera is required to photograph a body area."
        )
        XCTAssertEqual(Copy.outlinesUnavailable, "Outlines unavailable")
        XCTAssertEqual(
            Copy.lockedJournal,
            "This phone's journal belongs to a different Apple ID."
        )
    }
}
