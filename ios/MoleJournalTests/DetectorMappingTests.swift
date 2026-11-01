import CoreML
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

    func testLetterboxMatchesTheModelExport() {
        let portrait = letterboxPlacement(imageWidth: 800, imageHeight: 1600, modelWidth: 800, modelHeight: 800)
        XCTAssertEqual(portrait.resizedWidth, 400)
        XCTAssertEqual(portrait.resizedHeight, 800)
        XCTAssertEqual(portrait.padX, 200)
        XCTAssertEqual(portrait.padY, 0)

        let photo = letterboxPlacement(imageWidth: 4032, imageHeight: 3024, modelWidth: 800, modelHeight: 800)
        XCTAssertEqual(photo.resizedWidth, 800)
        XCTAssertEqual(photo.resizedHeight, 600)
        XCTAssertEqual(photo.padX, 0)
        XCTAssertEqual(photo.padY, 100)
    }

    func testEndToEndMoleBoxMapsThroughTheLetterbox() {
        let portrait = moleBoxesFromEndToEnd(
            rows: [[210, 20, 410, 820, 0.55, 1]],
            modelWidth: 800,
            modelHeight: 800,
            imageWidth: 800,
            imageHeight: 1600
        )
        XCTAssertEqual(portrait.count, 1)
        XCTAssertEqual(portrait[0].x, 20.0 / 800.0, accuracy: 0.0001)
        XCTAssertEqual(portrait[0].y, 40.0 / 1600.0, accuracy: 0.0001)
        XCTAssertEqual(portrait[0].width, 400.0 / 800.0, accuracy: 0.0001)
        XCTAssertEqual(portrait[0].height, 1560.0 / 1600.0, accuracy: 0.0001)
        XCTAssertEqual(portrait[0].label, "Mole")
        XCTAssertEqual(portrait[0].confidence, 0.55)

        let square = moleBoxesFromEndToEnd(
            rows: [[100, 100, 300, 200, 0.42, 1]],
            modelWidth: 800,
            modelHeight: 800,
            imageWidth: 800,
            imageHeight: 800
        )
        XCTAssertEqual(square[0].x, 0.125, accuracy: 0.0001)
        XCTAssertEqual(square[0].y, 0.125, accuracy: 0.0001)
        XCTAssertEqual(square[0].width, 0.25, accuracy: 0.0001)
        XCTAssertEqual(square[0].height, 0.125, accuracy: 0.0001)

        let landscape = moleBoxesFromEndToEnd(
            rows: [[0, 200, 800, 600, 0.30, 1]],
            modelWidth: 800,
            modelHeight: 800,
            imageWidth: 800,
            imageHeight: 400
        )
        XCTAssertEqual(landscape[0].x, 0, accuracy: 0.0001)
        XCTAssertEqual(landscape[0].y, 0, accuracy: 0.0001)
        XCTAssertEqual(landscape[0].width, 1, accuracy: 0.0001)
        XCTAssertEqual(landscape[0].height, 1, accuracy: 0.0001)
    }

    func testEndToEndDropsLowConfidenceAndTheImagesClass() {
        let kept = moleBoxesFromEndToEnd(
            rows: [
                [100, 100, 200, 200, 0.29, 1],
                [100, 100, 200, 200, 0.90, 0],
                [100, 100, 200, 200, 0.80, 1],
            ],
            modelWidth: 800,
            modelHeight: 800,
            imageWidth: 800,
            imageHeight: 800
        )
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept[0].confidence, 0.80)
    }

    func testEndToEndRowsReadTheModelArray() throws {
        let array = try MLMultiArray(shape: [1, 1, 6], dataType: .double)
        let values = [210.0, 20.0, 410.0, 820.0, 0.55, 1.0]
        for (component, value) in values.enumerated() {
            array[[NSNumber(value: 0), NSNumber(value: 0), NSNumber(value: component)]] = NSNumber(value: value)
        }
        let rows = try XCTUnwrap(endToEndRows(from: array))
        XCTAssertEqual(rows, [values])
        let anchors = try MLMultiArray(shape: [1, 6, 8], dataType: .double)
        XCTAssertNil(endToEndRows(from: anchors))
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
