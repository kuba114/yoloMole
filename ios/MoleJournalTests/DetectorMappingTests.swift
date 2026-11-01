import XCTest
@testable import MoleJournal

final class DetectorMappingTests: XCTestCase {
    func testPixelBoxBecomesFractionsOfTheUprightImage() {
        let box = normalizedRect(x1: 10, y1: 20, x2: 50, y2: 40, imageWidth: 200, imageHeight: 100)
        XCTAssertEqual(box.x, 0.05)
        XCTAssertEqual(box.y, 0.20)
        XCTAssertEqual(box.width, 0.20)
        XCTAssertEqual(box.height, 0.20)
        XCTAssertEqual(box.label, "Mole")
        XCTAssertFalse(box.hidden)
    }

    func testVisionBottomLeftBoxBecomesTopLeft() {
        let rect = topLeftRect(visionMinX: 0.10, visionMinY: 0.20, visionWidth: 0.30, visionHeight: 0.40)
        XCTAssertEqual(rect.x, 0.10, accuracy: 0.0001)
        XCTAssertEqual(rect.y, 0.40, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 0.30, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 0.40, accuracy: 0.0001)
    }

    func testBoxesBelowTheThresholdAreDropped() {
        let kept = keepMoleObservations([
            (label: "Mole", confidence: 0.30, x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            (label: "Mole", confidence: 0.29, x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            (label: "images", confidence: 0.90, x: 0.1, y: 0.1, width: 0.2, height: 0.2),
        ])
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept[0].confidence, 0.30)
    }
}
