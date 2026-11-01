import XCTest
@testable import MoleJournal

final class CaptureFlowTests: XCTestCase {
    func testRotatedSizeSwapsDimensions() {
        let size = uprightSize(width: 1920, height: 1080, orientationIsRotated: true)
        XCTAssertEqual(size.width, 1080)
        XCTAssertEqual(size.height, 1920)
    }

    func testZeroBoxesHaveNoUnavailableMessage() {
        let outcome = DetectionOutcome(boxes: [], outlinesUnavailable: false)
        XCTAssertNil(reviewMessage(outcome))
    }

    func testFailedDetectionShowsUnavailable() {
        let outcome = DetectionOutcome(boxes: [], outlinesUnavailable: true)
        XCTAssertEqual(reviewMessage(outcome), Copy.outlinesUnavailable)
    }

    func testAdvanceFromInstructionReachesCameraWithGhost() {
        var step = initialCaptureStep(previousImageFilename: "last.jpg")
        step = advanceToCamera(step)
        XCTAssertEqual(step.phase, .camera)
        XCTAssertTrue(step.showsGhost)
    }
}
