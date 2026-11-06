import UIKit
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

    func testFullCropKeepsTheOriginalPhoto() throws {
        let upright = try samplePhoto(width: 100, height: 80)
        let cropped = try XCTUnwrap(croppedUprightImage(upright, crop: .full))
        XCTAssertEqual(cropped.jpeg, upright.jpeg)
        XCTAssertEqual(cropped.width, 100)
        XCTAssertEqual(cropped.height, 80)
    }

    func testCropStoresOnlyTheSelectedSides() throws {
        let upright = try samplePhoto(width: 100, height: 80)
        let cropped = try XCTUnwrap(
            croppedUprightImage(upright, crop: CropRect(left: 0.5, top: 0, right: 1, bottom: 1))
        )
        let decoded = try XCTUnwrap(UIImage(data: cropped.jpeg)?.cgImage)
        XCTAssertEqual(decoded.width, 50)
        XCTAssertEqual(decoded.height, 80)
        XCTAssertEqual(cropped.width, 50)
        XCTAssertEqual(cropped.height, 80)
    }

    func testAdvanceFromInstructionReachesCameraWithGhost() {
        var step = initialCaptureStep(previousImageFilename: "last.jpg")
        step = advanceToCamera(step)
        XCTAssertEqual(step.phase, .camera)
        XCTAssertTrue(step.showsGhost)
    }

    private func samplePhoto(width: Int, height: Int) throws -> UprightImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try XCTUnwrap(jpegData(from: image))
    }
}
